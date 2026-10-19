import Foundation

/// 鸡丝此刻在做什么。每个 pose 只决定「图层组合 + 动画参数」，见 `CatLook`。
public enum CatPose: String, Codable, CaseIterable, Hashable, Sendable {
    /// 悠闲：呼吸 + 偶尔眨眼
    case lounging
    /// 活跃 / 摸鱼：歪头 + 道具
    case playing
    /// 困了：头下垂
    case drowsy
    /// 睡觉中：闭眼 + Zzz
    case sleeping
    /// 互动反应：被摸摸
    case petted
    /// 互动反应：吃小鱼干
    case fed
    /// 拍毛线球
    case batting
    /// 钻进纸箱只露出头
    case inBox
    /// 趴在软垫上打盹
    case cushionNap
    /// 伸懒腰
    case stretching
    /// 对着电脑假装工作
    case working

    public var isReaction: Bool { self == .petted || self == .fed }

    public var displayName: String {
        switch self {
        case .lounging: "悠闲"
        case .playing: "摸鱼中"
        case .drowsy: "困了"
        case .sleeping: "睡觉中"
        case .petted: "被摸摸"
        case .fed: "吃东西"
        case .batting: "玩毛线球"
        case .inBox: "钻纸箱"
        case .cushionNap: "软垫上打盹"
        case .stretching: "伸懒腰"
        case .working: "假装工作"
        }
    }
}

/// 摸鱼时手边的小东西。电脑、咖啡、逗猫棒一直在桌上；毛线球、纸箱要先得到（见 `NestItem`）。
public enum Toy: String, Codable, CaseIterable, Hashable, Sendable {
    case yarn, laptop, coffee, fishingRod, box

    /// JisiKit/Resources 里的图片名
    public var assetName: String {
        switch self {
        case .yarn: "ItemYarn"
        case .laptop: "PropLaptop"
        case .coffee: "PropCoffee"
        case .fishingRod: "PropFishingPole"
        case .box: "ItemBox"
        }
    }

    /// 桌上一直有的
    public static let deskProps: [Toy] = [.laptop, .coffee, .fishingRod]
}

/// 小窝里的物件：通过相处事件得到，每件都能互动。没有购买、积分或掉落。
public enum NestItem: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case yarn, box, cushion

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .yarn: "毛线球"
        case .box: "纸箱"
        case .cushion: "软垫"
        }
    }

    /// 点它时鸡丝做什么
    public var pose: CatPose {
        switch self {
        case .yarn: .batting
        case .box: .inBox
        case .cushion: .cushionNap
        }
    }

    public var interaction: InteractionKind {
        switch self {
        case .yarn: .yarn
        case .box: .box
        case .cushion: .cushion
        }
    }

    /// 自主行为里对应的玩具（软垫不算玩具）
    public var toy: Toy? {
        switch self {
        case .yarn: .yarn
        case .box: .box
        case .cushion: nil
        }
    }
}

public struct CatSnapshot: Codable, Hashable, Sendable {
    public var pose: CatPose
    public var line: String
    public var toy: Toy?
    public var date: Date

    public init(pose: CatPose, line: String, toy: Toy? = nil, date: Date) {
        self.pose = pose
        self.line = line
        self.toy = toy
        self.date = date
    }
}

/// 一天中的某个时刻（分钟数，0..<1440）。
public struct DayTime: Codable, Hashable, Comparable, Sendable {
    public var minutes: Int

    public init(_ hour: Int, _ minute: Int = 0) {
        minutes = ((hour * 60 + minute) % 1440 + 1440) % 1440
    }

    public var hour: Int { minutes / 60 }
    public var minute: Int { minutes % 60 }

    public static func < (lhs: DayTime, rhs: DayTime) -> Bool { lhs.minutes < rhs.minutes }

    /// 支持跨午夜的区间判断，[start, end)。
    public static func isWithin(_ t: DayTime, from start: DayTime, to end: DayTime) -> Bool {
        if start == end { return false }
        if start < end { return t >= start && t < end }
        return t >= start || t < end
    }
}

public struct Schedule: Codable, Hashable, Sendable {
    public var workStart: DayTime
    public var workEnd: DayTime
    public var lunch: DayTime
    public var dinner: DayTime
    public var bedtime: DayTime
    public var wake: DayTime
    /// Calendar weekday：1 = 周日 … 7 = 周六
    public var workdays: Set<Int>

    public init(
        workStart: DayTime = DayTime(9, 30),
        workEnd: DayTime = DayTime(18, 30),
        lunch: DayTime = DayTime(12, 0),
        dinner: DayTime = DayTime(18, 45),
        bedtime: DayTime = DayTime(23, 30),
        wake: DayTime = DayTime(7, 30),
        workdays: Set<Int> = [2, 3, 4, 5, 6]
    ) {
        self.workStart = workStart
        self.workEnd = workEnd
        self.lunch = lunch
        self.dinner = dinner
        self.bedtime = bedtime
        self.wake = wake
        self.workdays = workdays
    }

    public static let `default` = Schedule()

    public func isWorkday(_ date: Date, calendar: Calendar) -> Bool {
        workdays.contains(calendar.component(.weekday, from: date))
    }

    public func isWorkingHours(_ date: Date, calendar: Calendar) -> Bool {
        isWorkday(date, calendar: calendar)
            && DayTime.isWithin(date.dayTime(calendar), from: workStart, to: workEnd)
    }

    public func isSleepTime(_ date: Date, calendar: Calendar) -> Bool {
        DayTime.isWithin(date.dayTime(calendar), from: bedtime, to: wake)
    }

    /// 某天的下班时刻。
    public func clockOut(on date: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: workEnd.hour, minute: workEnd.minute, second: 0, of: date) ?? date
    }
}

public enum InteractionKind: String, Codable, Hashable, Sendable {
    case pet, feed
    /// 在小窝里点了毛线球 / 纸箱 / 软垫
    case yarn, box, cushion

    public var item: NestItem? {
        switch self {
        case .yarn: .yarn
        case .box: .box
        case .cushion: .cushion
        case .pet, .feed: nil
        }
    }
}

public struct Interaction: Codable, Hashable, Sendable {
    public var kind: InteractionKind
    public var date: Date

    public init(kind: InteractionKind, date: Date) {
        self.kind = kind
        self.date = date
    }
}

public enum CatEventKind: String, Codable, Hashable, Sendable {
    /// 「带鸡丝上班」
    case clockIn
    /// 「一起下班」
    case clockOut
    /// 饭点提醒里点了「吃了」
    case ateMeal
    /// 休息提醒里点了「休息了」
    case tookBreak
    /// 下班时回答「今天累不累」
    case moodEasy, moodOkay, moodTired
}

/// 下班时的心情（可跳过，不追问）。只记录用户自己选的，不做推断。
public enum ClockOutMood: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case easy, okay, tired

    public var id: String { rawValue }
    public var emoji: String {
        switch self {
        case .easy: "😌"
        case .okay: "🙂"
        case .tired: "😮‍💨"
        }
    }
    public var label: String {
        switch self {
        case .easy: "轻松"
        case .okay: "还行"
        case .tired: "好累"
        }
    }
    public var event: CatEventKind {
        switch self {
        case .easy: .moodEasy
        case .okay: .moodOkay
        case .tired: .moodTired
        }
    }
}

public struct CatEvent: Codable, Hashable, Sendable {
    public var kind: CatEventKind
    public var date: Date

    public init(kind: CatEventKind, date: Date) {
        self.kind = kind
        self.date = date
    }
}

/// 一次「带鸡丝上班」。用于 Live Activity 的恢复判断。
public struct WorkSession: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    public var expectedClockOut: Date
    public var endedAt: Date?
    /// 用户点了「一起下班」
    public var userEnded: Bool
    /// 用户在锁屏上把 Live Activity 划掉了
    public var userDismissed: Bool
    /// 当前对应的 Live Activity id（可能已被系统结束）
    public var activityID: String?

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        expectedClockOut: Date,
        endedAt: Date? = nil,
        userEnded: Bool = false,
        userDismissed: Bool = false,
        activityID: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.expectedClockOut = expectedClockOut
        self.endedAt = endedAt
        self.userEnded = userEnded
        self.userDismissed = userDismissed
        self.activityID = activityID
    }

    public var isOpen: Bool { endedAt == nil && !userEnded }
}

extension Date {
    public func dayTime(_ calendar: Calendar) -> DayTime {
        let c = calendar.dateComponents([.hour, .minute], from: self)
        return DayTime(c.hour ?? 0, c.minute ?? 0)
    }
}
