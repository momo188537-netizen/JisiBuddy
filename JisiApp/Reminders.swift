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

    func reschedule() async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(ID.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let settings = store.reminders
        guard settings.mealsEnabled || settings.breaksEnabled else { return }
        guard await requestAuthorizationIfNeeded() else { return }

        let s = store.schedule
        if settings.mealsEnabled {
            for weekday in 1...7 {
                add("lunch.\(weekday)", weekday: weekday, at: s.lunch, category: ID.mealCategory,
                    body: "饭点到啦，鸡丝也饿了。记得去吃饭～")
                add("dinner.\(weekday)", weekday: weekday, at: s.dinner, category: ID.mealCategory,
                    body: "晚饭时间！吃饱了再忙喵。")
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
                        add("break.\(weekday).\(i)", weekday: weekday, at: t, category: ID.breakCategory,
                            body: "起来伸个懒腰吧，鸡丝陪你一起。")
                    }
                    m += step
                    i += 1
                }
            }
        }
    }

    private func add(_ id: String, weekday: Int, at time: DayTime, category: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "鸡丝"
        content.body = body
        content.categoryIdentifier = category
        content.sound = .default
        var date = DateComponents()
        date.weekday = weekday
        date.hour = time.hour
        date.minute = time.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        center.add(UNNotificationRequest(identifier: ID.prefix + id, content: content, trigger: trigger))
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
        default: break
        }
    }
}
