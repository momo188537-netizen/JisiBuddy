import Foundation

/// Mac 菜单栏 App 和 iPhone 之间的局域网同步（Network.framework + Bonjour，不走 iCloud）。
///
/// iPhone 是准：会话、实时活动、手表同步都在 iPhone 上。Mac 收 iPhone 推来的 `PeerSnapshot` 存进自己的
/// SharedStore，用同一个 CatBrain 算鸡丝在干嘛；Mac 上点的按钮先在本地乐观执行，再作为 `PeerCommand`
/// 发给 iPhone，走 iPhone 原来的那套（`LiveActivityController`、`JisiActions`），iPhone 执行完再推给手表和 Mac。
///
/// 两边都在前台时同步；iPhone 退到后台连接会断，回前台自动重连。Mac 一直开着监听，iPhone 去找它。
public enum PeerSync {
    /// Bonjour 服务类型，两边 Info.plist 的 NSBonjourServices 要写同一个
    public static let serviceType = "_jisibuddy._tcp"
    /// 协议版本：对不上的消息直接丢掉
    public static let version = 1
    /// 一条消息最大多少字节（防止读到乱数据时分配过大的内存）
    public static let maxMessageBytes = 4 * 1024 * 1024
    /// Mac 离线时点的上班 / 下班，最多隔这么久送到 iPhone 还算数
    public static let workCommandMaxAge: TimeInterval = 12 * 3600
    /// 摸摸、喂食这些（按当时的时间记进今天的小事）
    public static let interactionMaxAge: TimeInterval = 24 * 3600
}

/// iPhone → Mac：鸡丝此刻的全部状态（Mac 用它在本地算 CatBrain）。
public struct PeerSnapshot: Codable, Hashable, Sendable {
    public var session: WorkSession?
    public var schedule: Schedule
    public var lastInteraction: Interaction?
    public var recentEvents: [CatEvent]
    public var diary: Diary
    public var lastFedAt: Date?
    public var meetingUntil: Date?
    public var preferences: Preferences
    /// 生成时间
    public var updatedAt: Date
    /// 这是对哪条 Mac 请求的回复（执行完之后的状态）
    public var replyTo: UUID?

    public init(session: WorkSession?, schedule: Schedule, lastInteraction: Interaction?, recentEvents: [CatEvent],
                diary: Diary, lastFedAt: Date?, meetingUntil: Date?, preferences: Preferences = Preferences(),
                updatedAt: Date, replyTo: UUID? = nil) {
        self.session = session
        self.schedule = schedule
        self.lastInteraction = lastInteraction
        self.recentEvents = recentEvents
        self.diary = diary
        self.lastFedAt = lastFedAt
        self.meetingUntil = meetingUntil
        self.preferences = preferences
        self.updatedAt = updatedAt
        self.replyTo = replyTo
    }
}

/// Mac → iPhone：在 Mac 上点了什么。
public struct PeerCommand: Codable, Hashable, Sendable, Identifiable {
    public enum Action: Codable, Hashable, Sendable {
        case clockIn, clockOut
        case pet, feed, ateMeal, tookBreak
        case play(NestItem)
        case mood(ClockOutMood)
        case startMeeting(minutes: Int)
        case endMeeting
        /// 不改任何东西，iPhone 回复此刻的状态
        case sync
    }

    public var action: Action
    public var id: UUID
    public var sentAt: Date

    public init(action: Action, id: UUID = UUID(), sentAt: Date) {
        self.action = action
        self.id = id
        self.sentAt = sentAt
    }
}

/// 线上的一条消息。
public enum PeerMessage: Codable, Hashable, Sendable {
    /// 连上后第一条：协议版本 + 设备名（显示「已连上 xxx」）
    case hello(version: Int, name: String)
    case snapshot(PeerSnapshot)
    case command(PeerCommand)
}

/// 消息编解码：4 字节大端长度 + JSON。
public enum PeerCodec {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    public static func frame(_ message: PeerMessage) -> Data? {
        guard let body = try? encoder.encode(message), body.count <= PeerSync.maxMessageBytes else { return nil }
        var length = UInt32(body.count).bigEndian
        var out = Data(bytes: &length, count: 4)
        out.append(body)
        return out
    }

    /// 帧头里的长度；不合法（太大）返回 nil，调用方应断开连接。
    public static func bodyLength(_ header: Data) -> Int? {
        guard header.count == 4 else { return nil }
        let n = header.reduce(0) { ($0 << 8) | Int($1) }
        return n <= PeerSync.maxMessageBytes ? n : nil
    }

    public static func decode(_ body: Data) -> PeerMessage? {
        try? decoder.decode(PeerMessage.self, from: body)
    }
}

/// 后最写者为准：收到的命令要不要执行、收到的状态要不要采纳。纯函数，有测试。
public enum PeerMerge {
    /// iPhone 收到 Mac 的上班 / 下班：只有比 iPhone 上最近一次上下班更晚，才执行（Mac 离线时点的，送到时可能已经过时）。
    public static func shouldApply(_ command: PeerCommand, session: WorkSession?, now: Date) -> Bool {
        let age = now.timeIntervalSince(command.sentAt)
        switch command.action {
        case .clockIn:
            guard age <= PeerSync.workCommandMaxAge else { return false }
            guard let s = session else { return true }
            if s.isOpen { return false }
            return command.sentAt > (s.endedAt ?? s.startedAt)
        case .clockOut:
            guard age <= PeerSync.workCommandMaxAge, let s = session, s.isOpen else { return false }
            return command.sentAt > s.startedAt
        case .pet, .feed, .ateMeal, .tookBreak, .play, .mood:
            return age <= PeerSync.interactionMaxAge
        case .startMeeting(let minutes):
            return command.sentAt.addingTimeInterval(Double(minutes) * 60) > now
        case .endMeeting, .sync:
            return true
        }
    }

    /// Mac 收到 iPhone 的状态：还有没送到 / 没回复的本地操作时不采纳，
    /// 免得连上的一瞬间 iPhone 推来的旧状态把 Mac 刚点的改回去。
    /// 收到最后一条待回复操作的回复时，才整份采纳。
    public static func shouldAdopt(_ snapshot: PeerSnapshot, pending: [UUID]) -> Bool {
        pending.allSatisfy { $0 == snapshot.replyTo }
    }
}

extension SharedStore {
    /// iPhone：此刻的状态推给 Mac
    public func peerSnapshot(now: Date = Date(), replyTo: UUID? = nil) -> PeerSnapshot {
        PeerSnapshot(session: session, schedule: schedule, lastInteraction: lastInteraction, recentEvents: recentEvents,
                     diary: diary, lastFedAt: lastFedAt, meetingUntil: meetingUntil, preferences: preferences,
                     updatedAt: now, replyTo: replyTo)
    }

    /// Mac：把 iPhone 推来的状态整份存下来
    public func adopt(_ s: PeerSnapshot) {
        session = s.session
        schedule = s.schedule
        lastInteraction = s.lastInteraction
        recentEvents = s.recentEvents
        diary = s.diary
        lastFedAt = s.lastFedAt
        meetingUntil = s.meetingUntil
        preferences = s.preferences
    }
}

/// Mac：在本地先把操作做掉（乐观更新），不等 iPhone。算法和 iPhone 上 `LiveActivityController.startWork / endWork`、
/// `MeetingMode` 一致，只是没有实时活动和通知。连上 iPhone 后以 iPhone 执行完的结果为准。
public enum PeerLocal {
    public static func apply(_ command: PeerCommand, to store: SharedStore, calendar: Calendar = .current) {
        let now = command.sentAt
        switch command.action {
        case .clockIn:
            guard store.session?.isOpen != true else { return }
            var clockOut = store.schedule.clockOut(on: now, calendar: calendar)
            if clockOut <= now { clockOut = now.addingTimeInterval(8 * 3600) }
            store.session = WorkSession(startedAt: now, expectedClockOut: clockOut)
            store.record(CatEvent(kind: .clockIn, date: now))
        case .clockOut:
            guard var s = store.session, s.isOpen else { return }
            s.userEnded = true
            s.endedAt = now
            store.session = s
            store.record(CatEvent(kind: .clockOut, date: now))
            store.meetingUntil = nil
        case .pet: store.record(Interaction(kind: .pet, date: now))
        case .feed: store.record(Interaction(kind: .feed, date: now))
        case .play(let item): store.record(Interaction(kind: item.interaction, date: now))
        case .ateMeal: store.record(CatEvent(kind: .ateMeal, date: now))
        case .tookBreak: store.record(CatEvent(kind: .tookBreak, date: now))
        case .mood(let m): store.record(CatEvent(kind: m.event, date: now))
        case .startMeeting(let minutes): store.meetingUntil = now.addingTimeInterval(Double(minutes) * 60)
        case .endMeeting: store.meetingUntil = nil
        case .sync: break
        }
    }
}

/// iPhone 执行了 Mac 发来的上班 / 下班后弹一条通知，让手机这边看得到（App 开着时也会弹横幅）。
public enum PeerNotice {
    public static let requestID = "jisi.mac.work"

    /// - delay: 送到 iPhone 时距离 Mac 上点击过了多久（iPhone 当时在后台、打开 App 才收到的情况）
    public static func text(for action: PeerCommand.Action, expectedClockOut: Date?, delay: TimeInterval,
                            calendar: Calendar = .current) -> (title: String, body: String)? {
        let late = delay >= 60 ? "（电脑上 \(minutesText(delay)) 前点的）" : ""
        switch action {
        case .clockIn:
            let end = expectedClockOut.map { "，\(clock($0, calendar: calendar)) 下班" } ?? ""
            return ("电脑上带鸡丝上班啦", "鸡丝已经在锁屏和灵动岛陪你了\(end)\(late)")
        case .clockOut:
            return ("电脑上和鸡丝一起下班啦", "今天辛苦啦，鸡丝回小窝了\(late)")
        default:
            return nil
        }
    }

    static func clock(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    static func minutesText(_ t: TimeInterval) -> String {
        let m = Int(t / 60)
        return m < 60 ? "\(m) 分钟" : "\(m / 60) 小时\(m % 60 == 0 ? "" : " \(m % 60) 分钟")"
    }
}
