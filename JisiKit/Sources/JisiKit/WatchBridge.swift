import Foundation
import JisiWatchKit

extension Notification.Name {
    /// 上班 / 一起下班之后发出（App 进程内），iPhone 端用它把新状态推给手表、刷新首页。
    public static let jisiWorkStateDidChange = Notification.Name("JisiWorkStateDidChange")
}

extension WatchState {
    /// iPhone 上的会话 → 推给手表的状态。
    public init(session: WorkSession?, schedule: Schedule, now: Date) {
        let open = session?.isOpen == true
        self.init(
            isWorking: open,
            startedAt: open ? session?.startedAt : nil,
            expectedClockOut: open ? session?.expectedClockOut : nil,
            workEndMinutes: schedule.workEnd.minutes,
            updatedAt: now
        )
    }
}

extension SharedStore {
    public func watchState(now: Date = Date()) -> WatchState {
        WatchState(session: session, schedule: schedule, now: now)
    }
}
