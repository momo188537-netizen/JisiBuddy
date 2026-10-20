import Foundation
import JisiWatchKit
import UserNotifications
import WatchConnectivity

/// 久坐提醒：手表自己在本地排通知（不经 iPhone，iPhone 也不发），轻敲手腕。
/// 每次上班状态 / 开会 / 间隔变了，或者点了「站起来了」，都整组重排。
@MainActor
final class StandReminder: NSObject {
    static let shared = StandReminder()

    private let center = UNUserNotificationCenter.current()
    private let store = WatchStateStore()
    private var authorized: Bool?

    func setUp() {
        center.delegate = self
        let done = UNNotificationAction(identifier: StandPlan.doneAction, title: "站起来了", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: StandPlan.category, actions: [done], intentIdentifiers: []),
        ])
    }

    /// 下一次提醒的时间（手表首页显示）
    func nextDate(for state: WatchState, now: Date = Date()) -> Date? {
        StandPlan.dates(state: state, lastStood: store.lastStood, now: now).first
    }

    func reschedule(for state: WatchState, now: Date = Date()) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(StandPlan.idPrefix) && !$0.hasSuffix(".test") }
        center.removePendingNotificationRequests(withIdentifiers: pending)

        let dates = StandPlan.dates(state: state, lastStood: store.lastStood, now: now)
        guard !dates.isEmpty, let interval = state.standInterval, await ensureAuthorized() else { return }
        for (i, date) in dates.enumerated() {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSince(now)), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: StandPlan.idPrefix + "\(i)",
                                                        content: content(interval: interval), trigger: trigger))
        }
    }

    /// iPhone 调试菜单里点的：1 分钟后来一条
    func scheduleTest() async {
        guard await ensureAuthorized() else { return }
        let interval = WatchModel.shared.state.standInterval ?? StandPlan.defaultInterval
        try? await center.add(UNNotificationRequest(identifier: StandPlan.idPrefix + "test",
                                                    content: content(interval: interval),
                                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)))
    }

    func stood(now: Date = Date()) async {
        store.lastStood = now
        await reschedule(for: WatchModel.shared.state, now: now)
        WatchModel.shared.didStand()
        // 让 iPhone 记进今天的小事（不在身边就排队）
        let payload = WatchCodec.payload(for: WatchCommand(action: .stood, sentAt: now))
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in WCSession.default.transferUserInfo(payload) }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func ensureAuthorized() async -> Bool {
        if let authorized { return authorized }
        let settings = await center.notificationSettings()
        let ok: Bool
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: ok = true
        case .denied: ok = false
        default: ok = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
        authorized = ok
        return ok
    }

    private func content(interval: Int) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = "鸡丝"
        c.body = StandPlan.body(interval: interval)
        c.categoryIdentifier = StandPlan.category
        // 有声音设置时手表会同时轻敲手腕
        c.sound = .default
        return c
    }
}

extension StandReminder: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.categoryIdentifier == StandPlan.category,
              response.actionIdentifier == StandPlan.doneAction else { return }
        await stood()
    }
}
