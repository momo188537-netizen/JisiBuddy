import Foundation

/// 下班时间的轻通知：只在正带着鸡丝上班时，到下班点发一条「鸡丝想回家了」，每天最多一次，休息日不发，下班后取消。
public enum ClockOutNotice {
    public static let requestID = "jisi.clockout"
    public static let category = "jisi.clockout"
    public static let clockOutAction = "jisi.clockout.go"

    /// 该在什么时候提醒；nil 表示这次不提醒。
    /// - deliveredDay: 今天（yyyymmdd）是否已经提醒过
    /// - meetingUntil: 下班点正好在开会，就等开完会再提醒
    public static func fireDate(session: WorkSession, schedule: Schedule, deliveredDay: Int?,
                                now: Date, meetingUntil: Date? = nil, calendar: Calendar = .current) -> Date? {
        guard session.isOpen else { return nil }
        var fire = session.expectedClockOut
        if let until = meetingUntil, fire >= now, fire < until { fire = until }
        guard fire > now, schedule.isWorkday(fire, calendar: calendar) else { return nil }
        if let deliveredDay, deliveredDay == Diary.dayKey(fire, calendar: calendar) { return nil }
        return fire
    }

    /// 之前排过、且时间已过的那条算是「已经提醒过了」。
    static func deliveredDay(scheduledAt: Date?, previous: Int?, now: Date, calendar: Calendar) -> Int? {
        if let s = scheduledAt, s <= now { return Diary.dayKey(s, calendar: calendar) }
        return previous
    }
}

#if os(iOS)
import UserNotifications

extension ClockOutNotice {
    /// 上班 / 恢复陪伴时调用。
    public static func schedule(for session: WorkSession, store: SharedStore = .shared, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
        let delivered = deliveredDay(scheduledAt: store.clockOutNoticeAt, previous: store.clockOutNoticeDeliveredDay,
                                     now: now, calendar: .current)
        store.clockOutNoticeDeliveredDay = delivered
        store.clockOutNoticeAt = nil
        guard let fire = fireDate(session: session, schedule: store.schedule, deliveredDay: delivered, now: now,
                                  meetingUntil: store.meetingUntil) else { return }
        switch await center.notificationSettings().authorizationStatus {
        case .denied: return
        case .notDetermined:
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        default: break
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fire.timeIntervalSince(now)), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: requestID, content: content(), trigger: trigger))
        store.clockOutNoticeAt = fire
    }

    public static func content(body: String = "到下班时间啦，鸡丝想回家了～") -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "鸡丝"
        content.body = body
        content.categoryIdentifier = category
        content.sound = .default
        if let attachment = faceAttachment() { content.attachments = [attachment] }
        return content
    }

    /// 一起下班后调用。
    public static func cancel(store: SharedStore = .shared, now: Date = Date()) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestID])
        store.clockOutNoticeDeliveredDay = deliveredDay(scheduledAt: store.clockOutNoticeAt,
                                                        previous: store.clockOutNoticeDeliveredDay, now: now, calendar: .current)
        store.clockOutNoticeAt = nil
    }

    public static var notificationCategory: UNNotificationCategory {
        UNNotificationCategory(identifier: category,
                               actions: [UNNotificationAction(identifier: clockOutAction, title: "一起下班", options: [])],
                               intentIdentifiers: [])
    }

    /// 通知里带鸡丝头像（系统会移走附件文件，所以拷一份）
    public static func faceAttachment() -> UNNotificationAttachment? {
        guard let src = JisiArt.faceURL else { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("jisi-\(UUID().uuidString).png")
        guard (try? FileManager.default.copyItem(at: src, to: tmp)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "jisi", url: tmp)
    }
}
#endif
