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

    public var isReaction: Bool { self == .petted || self == .fed }

    public var displayName: String {
        switch self {
        case .lounging: "悠闲"
        case .playing: "摸鱼中"
        case .drowsy: "困了"
        case .sleeping: "睡觉中"
        case .petted: "被摸摸"
        case .fed: "吃东西"
        }
    }
}

/// 摸鱼时手边的小玩具，P0 用 SF Symbols 占位。
public enum Toy: String, Codable, CaseIterable, Hashable, Sendable {
    case yarn, laptop, coffee, fishingRod, box

    public var symbolName: String {
        switch self {
        case .yarn: "circle.dotted.circle"
        case .laptop: "laptopcomputer"
        case .coffee: "cup.and.saucer.fill"
        case .fishingRod: "fish"
        case .box: "shippingbox.fill"
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
