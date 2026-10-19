import Foundation

/// 鸡丝的「大脑」：纯函数，同样的输入永远得到同样的 CatSnapshot。
///
/// 优先级：互动 > 事件 > 自主行为。
/// 自主行为按 15 分钟时间桶决定，种子 = hash(日期, 桶序号)，且不与上一个桶重复。
public enum CatBrain {
    public struct Input: Sendable {
        public var now: Date
        public var schedule: Schedule
        public var lastInteraction: Interaction?
        public var recentEvents: [CatEvent]
        public var toys: [Toy]
        public var calendar: Calendar

        public init(
            now: Date,
            schedule: Schedule = .default,
            lastInteraction: Interaction? = nil,
            recentEvents: [CatEvent] = [],
            toys: [Toy] = Toy.allCases,
            calendar: Calendar = .current
        ) {
            self.now = now
            self.schedule = schedule
            self.lastInteraction = lastInteraction
            self.recentEvents = recentEvents
            self.toys = toys
            self.calendar = calendar
        }
    }

    public static let bucketLength: TimeInterval = 15 * 60
    /// 摸摸 / 喂食后的反应持续多久
    public static let reactionDuration: TimeInterval = 2 * 60
    /// 事件（上班、下班、吃了饭）的台词持续多久
    public static let eventDuration: TimeInterval = 15 * 60

    public static func snapshot(_ input: Input) -> CatSnapshot {
        if let reaction = reaction(input) { return reaction }
        if let event = eventReaction(input) { return event }
        let b = autonomous(at: input.now, input: input)
        return CatSnapshot(pose: b.pose, line: b.line, toy: b.toy, date: input.now)
    }

    /// 预算 [start, start + duration) 内的快照，用于 Widget 时间线。
    /// 每个 15 分钟桶边界一条，外加互动 / 事件过期的时刻。
    public static func timeline(_ input: Input, duration: TimeInterval = 24 * 3600) -> [CatSnapshot] {
        let start = input.now
        let end = start.addingTimeInterval(duration)
        var dates: Set<Date> = [start]

        var t = bucketStart(containing: start, calendar: input.calendar).addingTimeInterval(bucketLength)
        while t < end {
            dates.insert(t)
            t = t.addingTimeInterval(bucketLength)
        }
        if let i = input.lastInteraction {
            let expiry = i.date.addingTimeInterval(reactionDuration)
            if expiry > start && expiry < end { dates.insert(expiry) }
        }
        for e in input.recentEvents {
            let expiry = e.date.addingTimeInterval(eventDuration)
            if expiry > start && expiry < end { dates.insert(expiry) }
        }

        return dates.sorted().map { date in
            var i = input
            i.now = date
            return snapshot(i)
        }
    }

    // MARK: - 互动

    static func reaction(_ input: Input) -> CatSnapshot? {
        guard let i = input.lastInteraction else { return nil }
        let age = input.now.timeIntervalSince(i.date)
        guard age >= 0, age < reactionDuration else { return nil }
        let seed = mix(UInt64(bitPattern: Int64(i.date.timeIntervalSince1970.rounded())))
        switch i.kind {
        case .pet:
            return CatSnapshot(pose: .petted, line: Lines.petted.pick(seed), date: input.now)
        case .feed:
            return CatSnapshot(pose: .fed, line: Lines.fed.pick(seed), date: input.now)
        }
    }

    // MARK: - 事件

    static func eventReaction(_ input: Input) -> CatSnapshot? {
        let recent = input.recentEvents
            .filter { e in
                let age = input.now.timeIntervalSince(e.date)
                return age >= 0 && age < eventDuration
            }
            .max { $0.date < $1.date }
        guard let e = recent else { return nil }
        let seed = mix(UInt64(bitPattern: Int64(e.date.timeIntervalSince1970.rounded())))
        let line: String = switch e.kind {
        case .clockIn: Lines.clockIn.pick(seed)
        case .clockOut: Lines.clockOut.pick(seed)
        case .ateMeal: Lines.ateMeal.pick(seed)
        case .tookBreak: Lines.tookBreak.pick(seed)
        }
        return CatSnapshot(pose: .lounging, line: line, date: input.now)
    }

    // MARK: - 自主行为

    struct Behavior: Hashable {
        var pose: CatPose
        var line: String
        var toy: Toy?
    }

    static func autonomous(at date: Date, input: Input) -> Behavior {
        let cal = input.calendar
        let dayStart = cal.startOfDay(for: date)
        let target = bucketIndex(of: date, dayStart: dayStart)
        let dayKey = dayKey(date, calendar: cal)

        // 从当天第一个桶顺推，保证「不与上一个桶重复」在任何时刻计算都一致。
        var previous: Behavior?
        for b in 0...target {
            let t = dayStart.addingTimeInterval(Double(b) * bucketLength)
            let pool = candidates(at: t, input: input)
            let seed = mix(dayKey &* 1_000 &+ UInt64(b))
            let choices = pool.count > 1 ? pool.filter { $0 != previous } : pool
            previous = choices[Int(seed % UInt64(choices.count))]
        }
        return previous!
    }

    static func candidates(at date: Date, input: Input) -> [Behavior] {
        let cal = input.calendar
        let s = input.schedule
        let now = date.dayTime(cal)

        if s.isSleepTime(date, calendar: cal) {
            return Lines.sleeping.map { Behavior(pose: .sleeping, line: $0) }
        }

        let lounging = Lines.lounging.map { Behavior(pose: .lounging, line: $0) }
        let drowsy = Lines.drowsy.map { Behavior(pose: .drowsy, line: $0) }
        let toys: [Toy?] = input.toys.isEmpty ? [nil] : input.toys
        let playing = zip(Lines.playing, Lines.playing.indices).map { line, idx in
            Behavior(pose: .playing, line: line, toy: toys[idx % toys.count])
        }

        let preBed = DayTime(s.bedtime.hour - 1, s.bedtime.minute)
        let napStart = DayTime(s.lunch.hour + 1, s.lunch.minute)
        let napEnd = DayTime(s.lunch.hour + 2, s.lunch.minute + 30)
        if DayTime.isWithin(now, from: preBed, to: s.bedtime)
            || DayTime.isWithin(now, from: napStart, to: napEnd) {
            return drowsy + lounging
        }
        if s.isWorkingHours(date, calendar: cal) {
            return lounging + playing
        }
        return lounging + playing + Array(drowsy.prefix(2))
    }

    // MARK: - 时间桶与种子

    public static func bucketStart(containing date: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        return dayStart.addingTimeInterval(Double(bucketIndex(of: date, dayStart: dayStart)) * bucketLength)
    }

    static func bucketIndex(of date: Date, dayStart: Date) -> Int {
        max(0, Int(date.timeIntervalSince(dayStart) / bucketLength))
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> UInt64 {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return UInt64((c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0))
    }

    /// SplitMix64。Swift 自带的 Hasher 每次进程启动都会换种子，App 和扩展会算出不同结果，所以不能用。
    static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Array where Element == String {
    func pick(_ seed: UInt64) -> String { self[Int(seed % UInt64(count))] }
}
