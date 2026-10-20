import Foundation

/// 手表和 iPhone 之间的同步（WatchConnectivity）。手表读不到 iPhone 的 App Group，
/// iPhone 把上班状态推过来，手表存进自己那边的 App Group，表盘复杂功能从那里读。
///
/// 这个模块只放纯数据和纯函数（再加一个头像视图），iPhone、手表 App、手表小组件三处共用，单元测试在 macOS 上跑。
public enum WatchSync {
    /// 手表端的 App Group（和 iPhone 同名，但在手表上是另一个容器）
    public static let appGroupID = "group.com.zixu.jisibuddy"
    /// 表盘复杂功能的 kind
    public static let complicationKind = "JisiWatchComplication"
    /// iPhone 收到手表请求时，超过这么久的就不执行了（transferUserInfo 可能排队很久才送到）
    public static let commandMaxAge: TimeInterval = 15 * 60

    static let stateKey = "state"
    static let commandKey = "command"
    static let standTestKey = "standTest"
    static let lastStoodKey = "lastStood"
}

/// iPhone → 手表：此刻的上班状态。
public struct WatchState: Codable, Hashable, Sendable {
    public var isWorking: Bool
    public var startedAt: Date?
    public var expectedClockOut: Date?
    /// 作息里的下班时刻（一天中的分钟数），手表先乐观显示「上班」时用来估算下班点
    public var workEndMinutes: Int
    /// 生成时间；旧的不覆盖新的
    public var updatedAt: Date
    /// 久坐提醒间隔（分钟），nil = 关。手表自己在本地排通知，iPhone 不发。
    public var standInterval: Int?
    /// 开会到几点（期间不提醒久坐）
    public var meetingUntil: Date?
    /// 午饭时刻（一天中的分钟数），前后半小时不提醒久坐
    public var lunchMinutes: Int?

    public init(isWorking: Bool, startedAt: Date? = nil, expectedClockOut: Date? = nil,
                workEndMinutes: Int = 18 * 60 + 30, updatedAt: Date,
                standInterval: Int? = nil, meetingUntil: Date? = nil, lunchMinutes: Int? = nil) {
        self.isWorking = isWorking
        self.startedAt = startedAt
        self.expectedClockOut = expectedClockOut
        self.workEndMinutes = workEndMinutes
        self.updatedAt = updatedAt
        self.standInterval = standInterval
        self.meetingUntil = meetingUntil
        self.lunchMinutes = lunchMinutes
    }

    /// 手表第一次打开、还没收到过 iPhone 的数据
    public static let initial = WatchState(isWorking: false, updatedAt: .distantPast)

    public func phase(at now: Date) -> WorkPhase {
        guard isWorking, let start = startedAt, let end = expectedClockOut else { return .off }
        return now < end ? .working(since: start, until: end) : .overtime(since: start, due: end)
    }

    /// 收到的状态能不能替换手里这份（乐观更新之后，晚到的旧状态不能把它改回去）。
    public func shouldReplace(_ current: WatchState) -> Bool {
        updatedAt >= current.updatedAt
    }

    /// 手表上点了按钮、还没等到 iPhone 回复时先显示的样子。下班点的算法和 iPhone 上 `startWork` 一致：
    /// 今天的下班时刻，已经过了就按 8 小时算。
    public func applying(_ action: WatchCommand.Action, at now: Date, calendar: Calendar = .current) -> WatchState {
        var s = self
        s.updatedAt = now
        switch action {
        case .clockIn:
            guard !isWorking else { return s }
            s.isWorking = true
            s.startedAt = now
            s.expectedClockOut = Self.clockOut(startingAt: now, workEndMinutes: workEndMinutes, calendar: calendar)
        case .clockOut:
            s.isWorking = false
            s.startedAt = nil
            s.expectedClockOut = nil
        case .sync, .stood:
            return self
        }
        return s
    }

    public static func clockOut(startingAt now: Date, workEndMinutes: Int, calendar: Calendar = .current) -> Date {
        let m = ((workEndMinutes % 1440) + 1440) % 1440
        let end = calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: now) ?? now
        return end > now ? end : now.addingTimeInterval(8 * 3600)
    }
}

public enum WorkPhase: Hashable, Sendable {
    /// 没在上班
    case off
    /// 上班中，还没到下班点
    case working(since: Date, until: Date)
    /// 已经到下班点了，还没点「一起下班」
    case overtime(since: Date, due: Date)

    public var isWorking: Bool { self != .off }
}

/// 手表 → iPhone：上班 / 一起下班，或者只要一份最新状态（手表 App 打开时）。
public struct WatchCommand: Codable, Hashable, Sendable {
    public enum Action: String, Codable, Sendable {
        case clockIn, clockOut
        /// 不改任何东西，iPhone 回复此刻的状态
        case sync
        /// 久坐提醒里点了「站起来了」，iPhone 记进今天的小事
        case stood
    }

    public var action: Action
    public var id: UUID
    public var sentAt: Date

    public init(action: Action, id: UUID = UUID(), sentAt: Date) {
        self.action = action
        self.id = id
        self.sentAt = sentAt
    }

    /// 排队太久的请求不执行（比如手机关机一晚上，第二天早上才收到「上班」）。
    public func isFresh(now: Date, maxAge: TimeInterval = WatchSync.commandMaxAge) -> Bool {
        now.timeIntervalSince(sentAt) <= maxAge
    }
}

/// WatchConnectivity 的字典只收属性列表类型，这里统一用 JSON Data 包一层。
public enum WatchCodec {
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

    public static func payload(for state: WatchState) -> [String: Any] {
        guard let data = try? encoder.encode(state) else { return [:] }
        return [WatchSync.stateKey: data]
    }

    public static func state(from payload: [String: Any]) -> WatchState? {
        guard let data = payload[WatchSync.stateKey] as? Data else { return nil }
        return try? decoder.decode(WatchState.self, from: data)
    }

    public static func payload(for command: WatchCommand) -> [String: Any] {
        guard let data = try? encoder.encode(command) else { return [:] }
        return [WatchSync.commandKey: data]
    }

    public static func command(from payload: [String: Any]) -> WatchCommand? {
        guard let data = payload[WatchSync.commandKey] as? Data else { return nil }
        return try? decoder.decode(WatchCommand.self, from: data)
    }

    /// iPhone 调试菜单：让手表 1 分钟后发一条久坐提醒
    public static let standTestPayload: [String: Any] = [WatchSync.standTestKey: true]

    public static func isStandTest(_ payload: [String: Any]) -> Bool {
        payload[WatchSync.standTestKey] as? Bool == true
    }
}

/// 手表端保存最近一次状态（App Group，表盘复杂功能读同一份）。
public struct WatchStateStore: @unchecked Sendable {
    let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: WatchSync.appGroupID) ?? .standard
    }

    public func load() -> WatchState? {
        defaults.data(forKey: WatchSync.stateKey).flatMap { try? WatchCodec.decoder.decode(WatchState.self, from: $0) }
    }

    public func save(_ state: WatchState) {
        guard let data = try? WatchCodec.encoder.encode(state) else { return }
        defaults.set(data, forKey: WatchSync.stateKey)
    }

    /// 上次在久坐提醒里点「站起来了」的时间
    public var lastStood: Date? {
        get { defaults.object(forKey: WatchSync.lastStoodKey) as? Date }
        nonmutating set { defaults.set(newValue, forKey: WatchSync.lastStoodKey) }
    }
}

/// 倒计时相关的纯函数。表盘上的数字本身用 `Text(timerInterval:)` 自己走秒，不靠刷新时间线。
public enum WatchCountdown {
    /// 时间线只需要在「到下班点」那一刻换一次样式（上班中 → 该下班啦）。
    public static func entryDates(for state: WatchState, now: Date) -> [Date] {
        if case .working(_, let until) = state.phase(at: now) { return [now, until] }
        return [now]
    }

    /// 环形进度：上班过去了多少（0...1）。
    public static func progress(since start: Date, until end: Date, now: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(start) / total))
    }

    /// 「2小时05分」「35分钟」「不到1分钟」，用在不走秒的说明文字里。
    public static func text(_ interval: TimeInterval) -> String {
        let minutes = Int(max(0, interval) / 60)
        if minutes < 1 { return "不到1分钟" }
        if minutes < 60 { return "\(minutes)分钟" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)小时" : String(format: "%d小时%02d分", h, m)
    }

    /// 「18:30」
    public static func clockText(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

/// 久坐提醒（只在手表上）：上班期间，从上班或上次「站起来了」开始，每隔 `standInterval` 分钟提醒一次，
/// 到下班点为止；开会期间、午饭前后半小时跳过。纯函数，手表 App 按它排本地通知。
public enum StandPlan {
    public static let choices = [45, 50, 60, 90]
    public static let defaultInterval = 50
    public static let category = "jisi.stand"
    public static let doneAction = "jisi.stand.done"
    public static let idPrefix = "jisi.stand."
    /// 一次最多排多少条（watchOS 每个 App 最多 64 条待发通知）
    public static let maxPending = 16

    /// 老设置（30～180 分钟、步长 15）迁到最接近的可选值
    public static func normalized(_ minutes: Int) -> Int {
        choices.min { abs($0 - minutes) < abs($1 - minutes) } ?? defaultInterval
    }

    public static func dates(state: WatchState, lastStood: Date?, now: Date, calendar: Calendar = .current) -> [Date] {
        guard let interval = state.standInterval, interval > 0,
              case .working(let since, let until) = state.phase(at: now) else { return [] }
        let step = TimeInterval(interval * 60)
        var anchor = since
        if let lastStood, lastStood > anchor { anchor = lastStood }
        var out: [Date] = []
        var t = anchor.addingTimeInterval(step)
        while t < until, out.count < maxPending {
            if t > now, !inMeeting(t, state: state, now: now), !nearLunch(t, state: state, calendar: calendar) {
                out.append(t)
            }
            t = t.addingTimeInterval(step)
        }
        return out
    }

    static func inMeeting(_ t: Date, state: WatchState, now: Date) -> Bool {
        guard let until = state.meetingUntil, until > now else { return false }
        return t < until
    }

    static func nearLunch(_ t: Date, state: WatchState, calendar: Calendar) -> Bool {
        guard let lunch = state.lunchMinutes else { return false }
        let c = calendar.dateComponents([.hour, .minute], from: t)
        return abs((c.hour ?? 0) * 60 + (c.minute ?? 0) - lunch) <= 30
    }

    public static func body(interval: Int) -> String {
        "坐了 \(interval) 分钟啦，站起来走走吧～鸡丝陪你伸个懒腰"
    }
}
