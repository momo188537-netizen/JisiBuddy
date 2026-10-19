import Foundation

/// 和鸡丝相处的流水账：只记真实发生过的互动和事件（次数、时间），不打分、不推断情绪。
/// 小窝物件的获得和纪念都从这里来。纯数据 + 纯函数，方便测试。
public struct Diary: Codable, Hashable, Sendable {
    /// 第一次有记录的时间
    public var firstDay: Date?
    /// 有过任何互动 / 事件的日子（yyyymmdd）
    public var activeDays: Set<Int> = []
    public var firstClockOut: Date?
    public var clockOutCount = 0
    public var mealCount = 0
    public var petCount = 0
    public var feedCount = 0
    /// 已得到的物件和得到的时间
    public var items: [NestItem: Date] = [:]
    /// 刚得到、还没在首页提示过的物件
    public var pendingGift: NestItem?
    public var memories: [Memory] = []
    /// 首页已经展示过的纪念
    public var seenMemoryIDs: Set<String> = []
    public var today = DayCounts()

    public init() {}

    public var ownedItems: Set<NestItem> { Set(items.keys) }

    /// 记一笔。返回这次新增的纪念（通常为空）。
    @discardableResult
    public mutating func record(_ kind: Kind, at date: Date, calendar: Calendar = .current) -> [Memory] {
        let before = memories.count
        let day = Self.dayKey(date, calendar: calendar)
        if firstDay == nil {
            firstDay = date
            add(Memory(id: "firstDay", date: date, title: "和鸡丝认识的第一天", detail: "\(Self.format(date, calendar))，鸡丝搬进了小窝。"))
        }
        activeDays.insert(day)
        if today.day != day { today = DayCounts(day: day) }

        switch kind {
        case .pet:
            petCount += 1
            today.pets += 1
        case .feed:
            feedCount += 1
            today.feeds += 1
        case .clockIn:
            if today.firstClockIn == nil { today.firstClockIn = date }
        case .clockOut:
            clockOutCount += 1
            today.clockOut = date
            if firstClockOut == nil {
                firstClockOut = date
                add(Memory(id: "firstClockOut", date: date, title: "第一次一起下班", detail: "\(Self.format(date, calendar))，你们一起下班回了小窝。"))
            }
            if Self.clockOutMilestones.contains(clockOutCount) {
                add(Memory(id: "clockOut.\(clockOutCount)", date: date, title: "一起下班 \(clockOutCount) 次", detail: "第 \(clockOutCount) 次是 \(Self.format(date, calendar))。"))
            }
        case .ateMeal:
            mealCount += 1
            today.meals += 1
            if Self.mealMilestones.contains(mealCount) {
                let title = mealCount == 1 ? "第一次一起吃饭" : "一起吃过 \(mealCount) 次饭"
                add(Memory(id: "meal.\(mealCount)", date: date, title: title, detail: "第 \(mealCount) 次是 \(Self.format(date, calendar))。"))
            }
        case .tookBreak:
            today.breaks += 1
        case .played:
            break
        }

        if let item = NestGifts.earned(after: kind, owned: ownedItems, activeDays: activeDays.count) {
            items[item] = date
            pendingGift = item
            add(Memory(id: "item.\(item.rawValue)", date: date, title: "得到了\(item.displayName)",
                       detail: "\(Self.format(date, calendar))，\(NestGifts.story(item, after: kind))"))
        }
        checkAnniversaries(now: date, calendar: calendar)
        return Array(memories[before...])
    }

    /// 相处满一周 / 一个月 / 100 天 / 一年。按认识的日期算，到了就记一笔，不需要每天打开。
    public mutating func checkAnniversaries(now: Date, calendar: Calendar = .current) {
        guard let first = firstDay else { return }
        let start = calendar.startOfDay(for: first)
        for (days, title) in Self.anniversaries {
            guard let date = calendar.date(byAdding: .day, value: days, to: start), date <= now else { continue }
            add(Memory(id: "days.\(days)", date: date, title: title,
                       detail: "从 \(Self.formatDay(first, calendar)) 认识到 \(Self.formatDay(date, calendar))。这期间一起度过了 \(activeDays.count) 天。"))
        }
    }

    /// 首页要提示的纪念：最新一条没看过的（低频，一次一条）。
    public var unseenMemory: Memory? {
        memories.filter { !seenMemoryIDs.contains($0.id) }.max { $0.date < $1.date }
    }

    /// 看过了：把现在所有纪念都标记为已看，避免连续弹好几条。
    public mutating func markMemoriesSeen() {
        seenMemoryIDs.formUnion(memories.map(\.id))
    }

    /// 从日志重放。补出来的纪念只在首页提示最新一条，物件不再弹「得到了」。
    public static func replaying(_ log: [(kind: String, date: Date)], now: Date = Date(), calendar: Calendar = .current) -> Diary {
        var d = Diary()
        for (kind, date) in log {
            guard let k = Kind(logKind: kind) else { continue }
            d.record(k, at: date, calendar: calendar)
        }
        d.checkAnniversaries(now: now, calendar: calendar)
        d.pendingGift = nil
        if let newest = d.unseenMemory {
            d.markMemoriesSeen()
            d.seenMemoryIDs.remove(newest.id)
        }
        return d
    }

    private mutating func add(_ memory: Memory) {
        guard !memories.contains(where: { $0.id == memory.id }) else { return }
        memories.append(memory)
    }

    // MARK: -

    public enum Kind: String, Codable, Hashable, Sendable {
        case pet, feed, clockIn, clockOut, ateMeal, tookBreak
        /// 在小窝里玩了物件
        case played
    }

    static let mealMilestones: Set<Int> = [1, 10, 30, 50, 100, 200, 365]
    static let clockOutMilestones: Set<Int> = [10, 50, 100, 200]
    static let anniversaries: [(Int, String)] = [(7, "相处一周"), (30, "相处一个月"), (100, "相处 100 天"), (365, "相处一年")]

    public static func dayKey(_ date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    static func format(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        return String(format: "%d月%d日 %02d:%02d", c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    static func formatDay(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0)月\(c.day ?? 0)日"
    }
}

/// 一条纪念：只写发生了什么、什么时候，不写「鸡丝很开心」之类的推断。
public struct Memory: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var date: Date
    public var title: String
    public var detail: String
}

/// 今天的小事（首页可折叠）。换天自动清零。
public struct DayCounts: Codable, Hashable, Sendable {
    public var day = 0
    public var pets = 0
    public var feeds = 0
    public var meals = 0
    public var breaks = 0
    public var firstClockIn: Date?
    public var clockOut: Date?

    public init(day: Int = 0) { self.day = day }

    public var isEmpty: Bool {
        pets == 0 && feeds == 0 && meals == 0 && breaks == 0 && firstClockIn == nil && clockOut == nil
    }
}

/// 物件怎么来：
/// - 毛线球：第一次「带鸡丝上班」
/// - 软垫：第一次「一起下班」
/// - 纸箱：第一次在提醒里点「吃了」或「休息了」
/// - 小惊喜：相处满 3 天时，如果还有没得到的，鸡丝会在门口「捡到」一件（每次最多一件）
public enum NestGifts {
    public static let surpriseAfterDays = 3

    public static func earned(after kind: Diary.Kind, owned: Set<NestItem>, activeDays: Int) -> NestItem? {
        let direct: NestItem? = switch kind {
        case .clockIn: .yarn
        case .clockOut: .cushion
        case .ateMeal, .tookBreak: .box
        default: nil
        }
        if let direct, !owned.contains(direct) { return direct }
        if activeDays >= surpriseAfterDays {
            return [NestItem.box, .yarn, .cushion].first { !owned.contains($0) }
        }
        return nil
    }

    static func story(_ item: NestItem, after kind: Diary.Kind) -> String {
        switch (item, kind) {
        case (.yarn, .clockIn): "第一次带鸡丝上班，路上捡到了一个毛线球。"
        case (.cushion, .clockOut): "第一次一起下班，小窝里多了一块软垫。"
        case (.box, .ateMeal): "你吃完饭回来，鸡丝发现了一个纸箱。"
        case (.box, .tookBreak): "你起来休息的时候，鸡丝发现了一个纸箱。"
        default: "鸡丝在门口发现了一个\(item.displayName)。"
        }
    }
}

/// 小窝场景的光线：白天 / 傍晚 / 夜里（按作息）。
public enum SceneLight: Sendable {
    case day, dusk, night

    public static func at(_ date: Date, schedule s: Schedule, calendar: Calendar = .current) -> SceneLight {
        let now = date.dayTime(calendar)
        if s.isSleepTime(date, calendar: calendar) { return .night }
        if DayTime.isWithin(now, from: DayTime(0, s.dinner.minutes + 45), to: s.bedtime) { return .night }
        if DayTime.isWithin(now, from: DayTime(0, s.workEnd.minutes - 60), to: DayTime(0, s.dinner.minutes + 45)) { return .dusk }
        if DayTime.isWithin(now, from: DayTime(0, 0), to: s.wake) { return .night }
        return .day
    }
}
