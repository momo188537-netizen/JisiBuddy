import Foundation
import JisiKit
import UIKit

/// iPhone 这头的 Mac 同步：App 在前台时在局域网里找 Mac 菜单栏 App，连上后状态一变就推过去；
/// Mac 上点的上班 / 下班 / 摸摸等，走和 App 自己同一套（`LiveActivityController`、`JisiActions`），
/// 实时活动、手表（`PhoneWatchLink` 听同一个通知）照常更新。
///
/// iOS 退到后台后连接会断（系统限制），回前台自动重连并互相补一次。
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
                MainActor.assumeIsolated { PhoneMacLink.shared.client.start() }
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { PhoneMacLink.shared.client.stop() }
            },
        ]
        if UIApplication.shared.applicationState != .background { client.start() }
    }

    var isConnected: Bool { client.isConnected }

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
        guard PeerMerge.shouldApply(command, session: store.session, now: now) else { return }
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
        case .clockOut:
            await live.endWork(now: min(at, now))
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
}
