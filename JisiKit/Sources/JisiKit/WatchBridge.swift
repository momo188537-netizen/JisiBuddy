import Foundation
import JisiWatchKit

extension Notification.Name {
    /// 上班 / 一起下班之后发出（App 进程内），iPhone 端用它把新状态推给手表、刷新首页。
    public static let jisiWorkStateDidChange = Notification.Name("JisiWorkStateDidChange")
}

extension WatchState {
    /// iPhone 上的会话 → 推给手表的状态。
    public init(session: WorkSession?, schedule: Schedule, now: Date,
                reminders: ReminderSettings = ReminderSettings(), meetingUntil: Date? = nil) {
        let open = session?.isOpen == true
        self.init(
            isWorking: open,
            startedAt: open ? session?.startedAt : nil,
            expectedClockOut: open ? session?.expectedClockOut : nil,
            workEndMinutes: schedule.workEnd.minutes,
            updatedAt: now,
            standInterval: reminders.breaksEnabled ? StandPlan.normalized(reminders.breakInterval) : nil,
            meetingUntil: meetingUntil.flatMap { $0 > now ? $0 : nil },
            lunchMinutes: schedule.lunch.minutes
        )
    }
}

extension SharedStore {
    public func watchState(now: Date = Date()) -> WatchState {
        WatchState(session: session, schedule: schedule, now: now, reminders: reminders, meetingUntil: meetingUntil)
    }
}

#if os(iOS)
import UserNotifications

/// 手表点「上班」时 iPhone App 在后台，iOS 不让开始实时活动（免费账号也没有推送启动）。
/// 这时发一条通知，点一下打开 App，回前台时自动把鸡丝放到锁屏和灵动岛（`ResumePolicy.shouldAutoStart`）。
public enum WatchStartNotice {
    public static let requestID = "jisi.watch.activity"

    static func post() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "鸡丝已经陪你上班啦"
        content.body = "点一下，把它放到锁屏和灵动岛"
        content.sound = .default
        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: nil)
        try? await center.add(request)
    }

    static func remove() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
        center.removeDeliveredNotifications(withIdentifiers: [requestID])
    }
}
#endif
