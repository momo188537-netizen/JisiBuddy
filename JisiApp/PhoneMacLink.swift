import Foundation
import JisiKit
import ActivityKit
import UIKit
import UserNotifications

/// iPhone 这头的 Mac 同步：App 在前台时在局域网里找 Mac 菜单栏 App，连上后状态一变就推过去；
/// Mac 上点的上班 / 下班 / 摸摸等，走和 App 自己同一套（`LiveActivityController`、`JisiActions`），
/// 实时活动、手表（`PhoneWatchLink` 听同一个通知）照常更新。
///
/// iOS 退到后台后连接会断（系统限制），回前台自动重连并互相补一次。退到后台后还多连 25 秒
/// （后台任务），刚切走时在 Mac 上点的上班 / 下班也能马上到；再晚的要等下次打开鸡丝。
@MainActor
final class PhoneMacLink {
    static let shared = PhoneMacLink()

    private let store = SharedStore.shared
    private let client = PeerClient()
    private var observers: [NSObjectProtocol] = []
    /// 执行过的 Mac 请求（Mac 重连后会把没收到回复的再发一遍）
    private var handled: [UUID] = []
    private var queue: Task<Void, Never>?

    func start() {
        client.onConnect = { [weak self] in
            guard let self else { return }
            self.client.send(.hello(version: PeerSync.version, name: UIDevice.current.name))
            self.push()
        }
        client.onMessage = { [weak self] message in
            self?.receive(message)
        }

        let center = NotificationCenter.default
        let push: @Sendable (Notification) -> Void = { _ in
            MainActor.assumeIsolated { PhoneMacLink.shared.push() }
        }
        observers = [
            center.addObserver(forName: .jisiWorkStateDidChange, object: nil, queue: .main, using: push),
            center.addObserver(forName: .jisiStoreDidChange, object: nil, queue: .main, using: push),
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { PhoneMacLink.shared.enterForeground() }
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { PhoneMacLink.shared.enterBackground() }
            },
        ]
        if UIApplication.shared.applicationState != .background { client.start() }
    }

    var isConnected: Bool { client.isConnected }

    // MARK: - 前后台

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var graceTimer: Task<Void, Never>?
    /// 退到后台后再保持连接多久（系统给后台任务大约 30 秒）
    static let backgroundGrace: Duration = .seconds(25)

    private func enterForeground() {
        graceTimer?.cancel()
        graceTimer = nil
        endBackgroundTask()
        client.start()
    }

    private func enterBackground() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "jisi.mac") {
            MainActor.assumeIsolated { PhoneMacLink.shared.stopInBackground() }
        }
        graceTimer = Task {
            try? await Task.sleep(for: Self.backgroundGrace)
            guard !Task.isCancelled else { return }
            stopInBackground()
        }
    }

    private func stopInBackground() {
        graceTimer?.cancel()
        graceTimer = nil
        client.stop()
        // 正在执行的 Mac 请求做完再让系统挂起
        let pending = queue
        Task {
            await pending?.value
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    func push(replyTo: UUID? = nil) {
        client.send(.snapshot(store.peerSnapshot(replyTo: replyTo)))
    }

    private func receive(_ message: PeerMessage) {
        switch message {
        case .hello(let version, _):
            if version != PeerSync.version { print("[mac] 协议版本不一致：\(version)") }
        case .command(let command):
            guard !handled.contains(command.id) else {
                push(replyTo: command.id)
                return
            }
            handled = Array((handled + [command.id]).suffix(200))
            // 一条一条按顺序执行（比如离线时先上班后摸摸）
            let previous = queue
            queue = Task {
                await previous?.value
                await handle(command)
                push(replyTo: command.id)
            }
        case .snapshot:
            break
        }
    }

    /// 执行 Mac 发来的请求（太旧、已经被 iPhone 上更晚的操作盖过的不执行，只回复当前状态）。
    func handle(_ command: PeerCommand, now: Date = Date()) async {
        let apply = PeerMerge.shouldApply(command, session: store.session, now: now)
        print("[mac] 收到 \(command.action)，前台：\(UIApplication.shared.applicationState == .active)，执行：\(apply)")
        defer { print("[mac] 执行完，实时活动：\(Activity<JisiActivityAttributes>.activities.map { "\($0.activityState)" })，会话开着：\(store.session?.isOpen == true)") }
        guard apply else { return }
        let at = command.sentAt
        let live = LiveActivityController.shared
        switch command.action {
        case .clockIn:
            do {
                // 刚点的按当时开始；Mac 离线时点的按 Mac 上点的时间算
                try await live.startWork(now: min(at, now), allowWithoutActivity: true)
            } catch {
                print("[mac] 上班失败：\(error)")
            }
            // 在后台没能开始实时活动时，startWork 已经发了「点一下放到锁屏」那条（和手表一样），不再重复
            if live.isRunning { await postNotice(command, now: now) }
        case .clockOut:
            await live.endWork(now: min(at, now))
            await postNotice(command, now: now)
        case .pet: await JisiActions.pet(at: at)
        case .feed: await JisiActions.feed(at: at)
        case .ateMeal: await JisiActions.ateMeal(at: at)
        case .tookBreak: await JisiActions.tookBreak(at: at)
        case .play(let item): await JisiActions.play(item, at: at)
        case .mood(let mood): await JisiActions.mood(mood, at: at)
        case .startMeeting(let minutes):
            // 按 Mac 上点的时间算散会点
            let left = at.addingTimeInterval(Double(minutes) * 60).timeIntervalSince(now) / 60
            await MeetingMode.start(minutes: max(1, Int(left.rounded())), now: now)
        case .endMeeting: await MeetingMode.end()
        case .sync: break
        }
    }

    /// Mac 上点的上班 / 下班在手机上弹一条（App 开着也弹横幅），不然手机这边看不出发生了什么
    private func postNotice(_ command: PeerCommand, now: Date) async {
        guard let text = PeerNotice.text(for: command.action, expectedClockOut: store.session?.expectedClockOut,
                                         delay: now.timeIntervalSince(command.sentAt)) else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        if let face = ClockOutNotice.faceAttachment() { content.attachments = [face] }
        center.removeDeliveredNotifications(withIdentifiers: [PeerNotice.requestID])
        try? await center.add(UNNotificationRequest(identifier: PeerNotice.requestID, content: content, trigger: nil))
    }
}
