import Foundation

public enum JisiConfig {
    /// 要和 App / Widget 两个 target 的 entitlements 保持一致。
    public static let appGroupID = "group.com.zixu.jisibuddy"
    public static let widgetKind = "JisiLockScreenWidget"
}

/// App 和扩展共享的轻量状态，存在 App Group 的 UserDefaults 里（JSON 编码）。
///
/// 如果 App Group 没签出来（免费账号的风险），`UserDefaults(suiteName:)` 仍会返回一个只属于本进程的实例，
/// App 和 Live Activity 照常工作，只是锁屏 Widget 看不到互动，退化为按作息自己演。
public final class SharedStore: @unchecked Sendable {
    public static let shared = SharedStore()

    let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: JisiConfig.appGroupID) ?? .standard
    }

    /// 能否真的写入 App Group 容器（用来在 App 里提示签名状态）。
    public static var isAppGroupAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: JisiConfig.appGroupID) != nil
    }

    enum Key: String {
        case schedule, lastInteraction, events, toys, snapshot, session, lastFedAt, reminders
    }

    func get<T: Decodable>(_ key: Key, as type: T.Type = T.self) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    func set<T: Encodable>(_ value: T?, for key: Key) {
        if let value, let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    public var schedule: Schedule {
        get { get(.schedule) ?? .default }
        set { set(newValue, for: .schedule) }
    }

    public var lastInteraction: Interaction? {
        get { get(.lastInteraction) }
        set { set(newValue, for: .lastInteraction) }
    }

    /// 只保留最近 24 小时的事件。
    public var recentEvents: [CatEvent] {
        get { get(.events) ?? [] }
        set {
            let cutoff = Date().addingTimeInterval(-24 * 3600)
            set(newValue.filter { $0.date > cutoff }.suffix(50), for: .events)
        }
    }

    public var toys: [Toy] {
        get { get(.toys) ?? Toy.allCases }
        set { set(newValue, for: .toys) }
    }

    public var lastFedAt: Date? {
        get { get(.lastFedAt) }
        set { set(newValue, for: .lastFedAt) }
    }

    public var session: WorkSession? {
        get { get(.session) }
        set { set(newValue, for: .session) }
    }

    public var reminders: ReminderSettings {
        get { get(.reminders) ?? ReminderSettings() }
        set { set(newValue, for: .reminders) }
    }

    // MARK: - 便捷操作

    public func brainInput(at now: Date = Date(), calendar: Calendar = .current) -> CatBrain.Input {
        CatBrain.Input(
            now: now,
            schedule: schedule,
            lastInteraction: lastInteraction,
            recentEvents: recentEvents,
            toys: toys,
            calendar: calendar
        )
    }

    public func snapshot(at now: Date = Date()) -> CatSnapshot {
        CatBrain.snapshot(brainInput(at: now))
    }

    public func record(_ interaction: Interaction) {
        lastInteraction = interaction
        if interaction.kind == .feed { lastFedAt = interaction.date }
    }

    public func record(_ event: CatEvent) {
        recentEvents = recentEvents + [event]
    }
}

public struct ReminderSettings: Codable, Hashable, Sendable {
    public var mealsEnabled: Bool
    public var breaksEnabled: Bool
    /// 工作时段内每隔多久提醒休息一次（分钟）
    public var breakInterval: Int

    public init(mealsEnabled: Bool = false, breaksEnabled: Bool = false, breakInterval: Int = 90) {
        self.mealsEnabled = mealsEnabled
        self.breaksEnabled = breaksEnabled
        self.breakInterval = breakInterval
    }
}
