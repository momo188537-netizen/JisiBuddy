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
    private(set) var diary = Diary()
    private(set) var light: SceneLight = .day
    private(set) var isRestDay = false
    private(set) var meetingUntil: Date?
    /// 刚在 App 里点了「一起下班」，问一句今天累不累（可跳过）
    private(set) var askMood = false

    var preferences: Preferences {
        get { store.preferences }
        set { store.preferences = newValue }
    }
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
        JisiLog.backfillDiaryIfNeeded()
        snapshot = SharedStore.shared.snapshot()
        schedule = SharedStore.shared.schedule
        diary = SharedStore.shared.diary
        light = SceneLight.at(Date(), schedule: SharedStore.shared.schedule)
        isRestDay = !SharedStore.shared.schedule.isWorkday(Date(), calendar: .current)
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
        var d = store.diary
        let count = d.memories.count
        d.checkAnniversaries(now: now)
        if d.memories.count != count { store.diary = d }
        diary = d
        light = SceneLight.at(now, schedule: store.schedule)
        isRestDay = !store.schedule.isWorkday(now, calendar: .current)
        meetingUntil = store.meetingUntil
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

    func startMeeting(minutes: Int) {
        Task {
            await MeetingMode.start(minutes: minutes)
            refresh()
        }
    }

    func endMeeting() {
        Task {
            await MeetingMode.end()
            refresh()
        }
    }

    /// 在小窝里点了物件
    func play(_ item: NestItem) {
        Task {
            await JisiActions.play(item)
            refresh()
        }
    }

    #if DEBUG
    func debugUnlockAllItems() {
        var d = store.diary
        for item in NestItem.allCases where d.items[item] == nil { d.items[item] = Date() }
        store.diary = d
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
    }
    #endif

    /// 从备份恢复（覆盖当前数据）
    func restore(_ backup: JisiBackup) {
        store.restore(backup)
        JisiLog.replaceAll(with: backup.log)
        schedule = store.schedule
        reminders = store.reminders
        refresh()
        WidgetCenter.shared.reloadAllTimelines()
        Task {
            await live.refresh()
            await Reminders.shared.reschedule()
        }
    }

    /// 首页的回忆卡片看过了
    func markMemoriesSeen() {
        var d = store.diary
        d.markMemoriesSeen()
        store.diary = d
        refresh()
    }

    /// 关掉「得到了新物件」的提示
    func dismissGift() {
        var d = store.diary
        d.pendingGift = nil
        store.diary = d
        refresh()
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
            askMood = store.preferences.askMoodAtClockOut
            refresh()
        }
    }

    func answerMood(_ mood: ClockOutMood?) {
        askMood = false
        guard let mood else { return }
        reactionID = Date()
        Task {
            await JisiActions.mood(mood)
            refresh()
        }
    }
}
