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
        /// 已得到的小窝物件（软垫只在这里体现）
        public var items: Set<NestItem>
        public var calendar: Calendar

        public init(
            now: Date,
            schedule: Schedule = .default,
            lastInteraction: Interaction? = nil,
            recentEvents: [CatEvent] = [],
            toys: [Toy] = Toy.allCases,
            items: Set<NestItem> = [],
            calendar: Calendar = .current
        ) {
            self.now = now
            self.schedule = schedule
            self.lastInteraction = lastInteraction
            self.recentEvents = recentEvents
            self.toys = toys
            self.items = items
            self.calendar = calendar
        }
    }

    public static let bucketLength: TimeInterval = 15 * 60
    /// 摸摸 / 喂食后的反应持续多久
    public static let reactionDuration: TimeInterval = 2 * 60
    /// 玩小窝物件（毛线球、纸箱、软垫）持续多久
    public static let itemDuration: TimeInterval = 5 * 60

    public static func duration(of kind: InteractionKind) -> TimeInterval {
        kind.item == nil ? reactionDuration : itemDuration
    }
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
            let expiry = i.date.addingTimeInterval(CatBrain.duration(of: i.kind))
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
        guard age >= 0, age < duration(of: i.kind) else { return nil }
        let seed = mix(UInt64(bitPattern: Int64(i.date.timeIntervalSince1970.rounded())))
        switch i.kind {
        case .pet:
            return CatSnapshot(pose: .petted, line: Lines.petted.pick(seed), date: input.now)
        case .feed:
            return CatSnapshot(pose: .fed, line: Lines.fed.pick(seed), date: input.now)
        case .yarn:
            return CatSnapshot(pose: .batting, line: Lines.batting.pick(seed), toy: .yarn, date: input.now)
        case .box:
            return CatSnapshot(pose: .inBox, line: Lines.inBox.pick(seed), toy: .box, date: input.now)
        case .cushion:
            return CatSnapshot(pose: .cushionNap, line: Lines.cushionNap.pick(seed), date: input.now)
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
        // 用户吃饭了，鸡丝也吃小鱼干（PRD 第 4 节）。
        let pose: CatPose = e.kind == .ateMeal ? .fed : .lounging
        return CatSnapshot(pose: pose, line: line, date: input.now)
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

        // 从当天第一个桶顺推，保证「不与上一个桶重复」「最近几句不重样」在任何时刻计算都一致。
        var previous: Behavior?
        var recentLines: [String] = []
        for b in 0...target {
            let t = dayStart.addingTimeInterval(Double(b) * bucketLength)
            let pool = candidates(at: t, input: input)
            let seed = mix(dayKey &* 1_000 &+ UInt64(b))
            var choices = pool.filter { $0 != previous && !recentLines.contains($0.line) }
            if choices.isEmpty { choices = pool.count > 1 ? pool.filter { $0 != previous } : pool }
            let pick = choices[Int(seed % UInt64(choices.count))]
            previous = pick
            recentLines.append(pick.line)
            if recentLines.count > recentLineMemory { recentLines.removeFirst() }
        }
        return previous!
    }

    /// 最近这么多句台词里不重复
    static let recentLineMemory = 6

    /// 一天里的时间段（按作息算）。
    enum Period: Equatable {
        case night, morning, workMorning, mealtime, afternoonSlump, workAfternoon, evening, preBed, weekend
    }

    static func period(at date: Date, schedule s: Schedule, calendar cal: Calendar) -> Period {
        let now = date.dayTime(cal)
        if s.isSleepTime(date, calendar: cal) { return .night }
        func within(_ from: DayTime, minutes: Int) -> Bool {
            DayTime.isWithin(now, from: from, to: DayTime(0, from.minutes + minutes))
        }
        if within(DayTime(0, s.bedtime.minutes - 60), minutes: 60) { return .preBed }
        if within(DayTime(0, s.lunch.minutes - 30), minutes: 90) || within(DayTime(0, s.dinner.minutes - 30), minutes: 75) {
            return .mealtime
        }
        if within(DayTime(0, s.lunch.minutes + 60), minutes: 90) { return .afternoonSlump }
        guard s.isWorkday(date, calendar: cal) else { return .weekend }
        if DayTime.isWithin(now, from: s.workStart, to: s.workEnd) {
            return now < s.lunch ? .workMorning : .workAfternoon
        }
        if DayTime.isWithin(now, from: s.wake, to: s.workStart) { return .morning }
        return .evening
    }

    static func candidates(at date: Date, input: Input) -> [Behavior] {
        let toys = Set(input.toys)
        let hasCushion = input.items.contains(.cushion)
        func make(_ pose: CatPose, _ lines: [String], toy: Toy? = nil) -> [Behavior] {
            if let toy, !toys.contains(toy) { return [] }
            return lines.map { Behavior(pose: pose, line: $0, toy: toy) }
        }
        // 摸鱼小动作：手边有什么玩什么
        let mischief = make(.playing, Lines.coffee, toy: .coffee)
            + make(.playing, Lines.fishing, toy: .fishingRod)
            + make(.batting, Lines.batting, toy: .yarn)
            + make(.inBox, Lines.inBox, toy: .box)
        let working = make(.working, Lines.working, toy: .laptop)
        let stretching = make(.stretching, Lines.stretching)
        let cushion = hasCushion ? make(.cushionNap, Lines.cushionNap) : []

        switch period(at: date, schedule: input.schedule, calendar: input.calendar) {
        case .night:
            return hasCushion ? make(.cushionNap, Lines.sleeping) : make(.sleeping, Lines.sleeping)
        case .morning:
            return make(.lounging, Lines.morning) + stretching
        case .workMorning:
            return make(.lounging, Lines.workMorning) + working + mischief + stretching
        case .mealtime:
            return make(.lounging, Lines.mealtime) + make(.playing, Lines.coffee, toy: .coffee)
        case .afternoonSlump:
            // 睡键盘：困得趴在电脑上，但不算真的睡着
            return make(.drowsy, Lines.afternoonSlump) + make(.drowsy, Lines.keyboardNap, toy: .laptop) + cushion
        case .workAfternoon:
            return make(.lounging, Lines.workAfternoon) + working + mischief + stretching
        case .evening:
            return make(.lounging, Lines.evening) + mischief + stretching + cushion
        case .preBed:
            return make(.drowsy, Lines.preBed) + cushion
        case .weekend:
            return make(.lounging, Lines.weekend) + mischief + stretching + cushion
        }
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
