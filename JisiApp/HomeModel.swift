import JisiKit
import Observation
import SwiftUI
import WidgetKit

@MainActor
@Observable
final class HomeModel {
    private let store = SharedStore.shared
    private let live = LiveActivityController.shared

    private(set) var snapshot: CatSnapshot
    private(set) var reactionID: Date?
    private(set) var isWorking = false
    private(set) var offerResume = false
    private(set) var session: WorkSession?
    private(set) var isBusy = false
    var errorMessage: String?

    var schedule: Schedule {
        didSet {
            guard schedule != oldValue else { return }
            store.schedule = schedule
            refresh()
            WidgetCenter.shared.reloadAllTimelines()
            Task { await Reminders.shared.reschedule() }
        }
    }

    var reminders: ReminderSettings {
        didSet {
            guard reminders != oldValue else { return }
            store.reminders = reminders
            Task { await Reminders.shared.reschedule() }
        }
    }

    let appGroupOK = SharedStore.isAppGroupAvailable

    init() {
        snapshot = SharedStore.shared.snapshot()
        schedule = SharedStore.shared.schedule
        reminders = SharedStore.shared.reminders
        live.reattach()
    }

    func onForeground() {
        refresh()
        Task { await live.refresh() }
        Task { await Reminders.shared.reschedule() }
    }

    func refresh(now: Date = Date()) {
        snapshot = store.snapshot(at: now)
        session = store.session
        isWorking = live.isWorking
        offerResume = live.shouldOfferResume(now: now)
    }

    func pet() {
        reactionID = Date()
        Task {
            await JisiActions.pet()
            refresh()
        }
    }

    func feed() {
        reactionID = Date()
        Task {
            await JisiActions.feed()
            refresh()
        }
    }

    /// 「带鸡丝上班」，也用于「继续陪伴」恢复（由用户点击触发，绝不自动重启）。
    func startWork() {
        guard live.areActivitiesEnabled else {
            errorMessage = "实时活动被关掉了，可以在 设置 > 鸡丝 里打开。"
            return
        }
        guard !isBusy else { return }
        isBusy = true
        Task {
            do {
                try await live.startWork()
            } catch {
                errorMessage = "鸡丝没能出门：\(error.localizedDescription)"
            }
            isBusy = false
            refresh()
        }
    }

    func endWork() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            await live.endWork()
            isBusy = false
            refresh()
        }
    }
}
