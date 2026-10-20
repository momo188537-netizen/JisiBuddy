import Foundation

/// 饭点提醒排哪些。纯函数：排未来几天的单次提醒，开会期间的跳过。
///
/// 「休息提醒」现在是手表上的久坐提醒（`StandPlan`，手表本地排），iPhone 不再发，免得锁屏时转发到手表重复。
///
/// 为什么不用每周重复的通知：重复通知没法只跳过某一次（开会时），所以改成每次排未来 7 天的单次提醒，
/// 每次打开 App、点锁屏按钮、开会 / 散会时都会重排。iOS 最多保留 64 条，这里最多排 60 条（最近的优先）。
public enum ReminderPlan {
    public static let maxPending = 60
    public static let mealCategory = "jisi.meal"
    public static let breakCategory = "jisi.break"

    public struct Item: Hashable, Sendable {
        public var id: String
        public var date: Date
        public var category: String
        public var body: String
    }

    public static func upcoming(settings: ReminderSettings, schedule s: Schedule, now: Date, meetingUntil: Date? = nil,
                                days: Int = 7, calendar: Calendar = .current) -> [Item] {
        guard settings.mealsEnabled else { return [] }
        var items: [Item] = []
        let today = calendar.startOfDay(for: now)
        for d in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: d, to: today) else { continue }
            let key = Diary.dayKey(day, calendar: calendar)
            func at(_ t: DayTime) -> Date? { calendar.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: day) }
            if settings.mealsEnabled {
                if let t = at(s.lunch) { items.append(Item(id: "lunch.\(key)", date: t, category: mealCategory, body: "饭点到啦，鸡丝也饿了。记得去吃饭～")) }
                if let t = at(s.dinner) { items.append(Item(id: "dinner.\(key)", date: t, category: mealCategory, body: "晚饭时间！吃饱了再忙喵。")) }
            }
        }
        return items
            .filter { $0.date > now && !isDuringMeeting($0.date, now: now, until: meetingUntil) }
            .sorted { $0.date < $1.date }
            .prefix(maxPending)
            .map { $0 }
    }

    static func isDuringMeeting(_ date: Date, now: Date, until: Date?) -> Bool {
        guard let until else { return false }
        return date >= now && date < until
    }
}

#if os(iOS)
import UserNotifications

/// 可选的本地饭点 / 休息提醒。没有惩罚，点不点都行。
@MainActor
public final class Reminders {
    public static let shared = Reminders()

    public enum ID {
        public static let mealCategory = ReminderPlan.mealCategory
        public static let breakCategory = ReminderPlan.breakCategory
        public static let ateAction = "jisi.ate"
        public static let restedAction = "jisi.rested"
        public static let prefix = "jisi.reminder."
    }

    private let center = UNUserNotificationCenter.current()
    private let store = SharedStore.shared

    public func registerCategories() {
        let ate = UNNotificationAction(identifier: ID.ateAction, title: "吃了", options: [])
        let rested = UNNotificationAction(identifier: ID.restedAction, title: "休息了", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: ID.mealCategory, actions: [ate], intentIdentifiers: []),
            UNNotificationCategory(identifier: ID.breakCategory, actions: [rested], intentIdentifiers: []),
            ClockOutNotice.notificationCategory,
        ])
    }

    /// 打开任何一种提醒时才申请通知权限。
    public func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    public func reschedule(now: Date = Date()) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(ID.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let settings = store.reminders
        guard settings.mealsEnabled else { return }
        guard await requestAuthorizationIfNeeded() else { return }

        let calendar = Calendar.current
        for item in ReminderPlan.upcoming(settings: settings, schedule: store.schedule, now: now, meetingUntil: store.meetingUntil) {
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: ID.prefix + item.id,
                                                        content: content(category: item.category, body: item.body), trigger: trigger))
        }
    }

    /// 调试用：1 分钟后发一条饭点提醒，带「吃了」按钮。
    public func sendTestMeal() async {
        guard await requestAuthorizationIfNeeded() else { return }
        try? await center.add(UNNotificationRequest(identifier: "jisi.test.meal",
                                                    content: content(category: ID.mealCategory, body: "（测试）饭点到啦，鸡丝也饿了。记得去吃饭～"),
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)))
    }

    /// 调试用：1 分钟后发一条下班提醒，带「一起下班」按钮。
    public func sendTestClockOut() async {
        guard await requestAuthorizationIfNeeded() else { return }
        try? await center.add(UNNotificationRequest(identifier: "jisi.test.clockout",
                                                    content: ClockOutNotice.content(body: "（测试）到下班时间啦，鸡丝想回家了～"),
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)))
    }

    private func content(category: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "鸡丝"
        content.body = body
        content.categoryIdentifier = category
        content.sound = .default
        return content
    }
}
#endif
