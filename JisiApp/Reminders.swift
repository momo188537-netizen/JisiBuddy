import JisiKit
import UIKit
import UserNotifications

/// 可选的本地饭点 / 休息提醒。没有惩罚，点不点都行。
@MainActor
final class Reminders {
    static let shared = Reminders()

    enum ID {
        static let mealCategory = "jisi.meal"
        static let breakCategory = "jisi.break"
        static let ateAction = "jisi.ate"
        static let restedAction = "jisi.rested"
        static let prefix = "jisi.reminder."
    }

    private let center = UNUserNotificationCenter.current()
    private let store = SharedStore.shared

    func registerCategories() {
        let ate = UNNotificationAction(identifier: ID.ateAction, title: "吃了", options: [])
        let rested = UNNotificationAction(identifier: ID.restedAction, title: "休息了", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: ID.mealCategory, actions: [ate], intentIdentifiers: []),
            UNNotificationCategory(identifier: ID.breakCategory, actions: [rested], intentIdentifiers: []),
            ClockOutNotice.notificationCategory,
        ])
    }

    /// 打开任何一种提醒时才申请通知权限。
    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    /// iOS 最多保留 64 条待发通知，超出的会被悄悄丢掉；留点余量，优先排最近要响的。
    static let maxPending = 60

    struct Planned {
        var id: String
        var weekday: Int
        var time: DayTime
        var category: String
        var body: String
    }

    func reschedule() async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(ID.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let settings = store.reminders
        guard settings.mealsEnabled || settings.breaksEnabled else { return }
        guard await requestAuthorizationIfNeeded() else { return }

        var plan: [Planned] = []
        let s = store.schedule
        if settings.mealsEnabled {
            for weekday in 1...7 {
                plan.append(.init(id: "lunch.\(weekday)", weekday: weekday, time: s.lunch, category: ID.mealCategory,
                                  body: "饭点到啦，鸡丝也饿了。记得去吃饭～"))
                plan.append(.init(id: "dinner.\(weekday)", weekday: weekday, time: s.dinner, category: ID.mealCategory,
                                  body: "晚饭时间！吃饱了再忙喵。"))
            }
        }
        if settings.breaksEnabled {
            let step = max(30, settings.breakInterval)
            for weekday in s.workdays {
                var m = s.workStart.minutes + step
                var i = 0
                while m < s.workEnd.minutes {
                    let t = DayTime(0, m)
                    // 饭点前后半小时不打扰
                    if abs(t.minutes - s.lunch.minutes) > 30 {
                        plan.append(.init(id: "break.\(weekday).\(i)", weekday: weekday, time: t, category: ID.breakCategory,
                                          body: "起来伸个懒腰吧，鸡丝陪你一起。"))
                    }
                    m += step
                    i += 1
                }
            }
        }

        // 每次回到 App 都会重排，所以只排最近的 maxPending 条也不会漏。
        let now = Date()
        let calendar = Calendar.current
        let soonest = plan
            .compactMap { p in calendar.nextDate(after: now, matching: components(p), matchingPolicy: .nextTime).map { (p, $0) } }
            .sorted { $0.1 < $1.1 }
            .prefix(Self.maxPending)
        for (p, _) in soonest {
            let trigger = UNCalendarNotificationTrigger(dateMatching: components(p), repeats: true)
            try? await center.add(UNNotificationRequest(identifier: ID.prefix + p.id, content: content(category: p.category, body: p.body), trigger: trigger))
        }
    }

    /// 调试用：1 分钟后发一条饭点提醒，带「吃了」按钮。
    func sendTestMeal() async {
        guard await requestAuthorizationIfNeeded() else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "jisi.test.meal",
                                         content: content(category: ID.mealCategory, body: "（测试）饭点到啦，鸡丝也饿了。记得去吃饭～"),
                                         trigger: trigger))
    }

    /// 调试用：1 分钟后发一条下班提醒，带「一起下班」按钮。
    func sendTestClockOut() async {
        guard await requestAuthorizationIfNeeded() else { return }
        try? await center.add(UNNotificationRequest(identifier: "jisi.test.clockout",
                                                    content: ClockOutNotice.content(body: "（测试）到下班时间啦，鸡丝想回家了～"),
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)))
    }

    private func components(_ p: Planned) -> DateComponents {
        var date = DateComponents()
        date.weekday = p.weekday
        date.hour = p.time.hour
        date.minute = p.time.minute
        return date
    }

    private func content(category: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "鸡丝"
        content.body = body
        content.categoryIdentifier = category
        content.sound = .default
        if let attachment = faceAttachment() { content.attachments = [attachment] }
        return content
    }

    /// 通知里带鸡丝头像。系统会把附件文件移走，所以每条都拷一份临时文件。
    private func faceAttachment() -> UNNotificationAttachment? {
        guard let src = JisiArt.faceURL else { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("jisi-\(UUID().uuidString).png")
        do {
            try FileManager.default.copyItem(at: src, to: tmp)
            return try UNNotificationAttachment(identifier: "jisi", url: tmp)
        } catch {
            return nil
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in Reminders.shared.registerCategories() }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        switch response.actionIdentifier {
        case Reminders.ID.ateAction: await JisiActions.ateMeal()
        case Reminders.ID.restedAction: await JisiActions.tookBreak()
        case ClockOutNotice.clockOutAction: await LiveActivityController.shared.endWork()
        default: break
        }
    }
}
