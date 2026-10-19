import Foundation
import JisiKit
import JisiWatchKit
import UIKit
import WatchConnectivity

/// iPhone 这头的手表同步：上班状态一变就 `updateApplicationContext` 推给手表；
/// 手表点「上班」「一起下班」时，走和 App / 快捷指令同一套 `LiveActivityController`，实时活动、小组件照常更新。
///
/// 在 AppDelegate 里启动。快捷指令、控制中心这些 `LiveActivityIntent` 也在 App 进程里跑，同样会推；
/// 小组件扩展进程里点的下班推不了，等下次 App 启动 / 回前台时补推。
@MainActor
final class PhoneWatchLink: NSObject {
    static let shared = PhoneWatchLink()

    private let store = SharedStore.shared
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .jisiWorkStateDidChange, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { PhoneWatchLink.shared.push() }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { PhoneWatchLink.shared.push() }
            },
        ]
    }

    /// 把此刻的状态推给手表（只留最新一份，手表下次醒来就能拿到）。
    func push(now: Date = Date()) {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        do {
            try session.updateApplicationContext(WatchCodec.payload(for: store.watchState(now: now)))
        } catch {
            print("[watch] updateApplicationContext 失败：\(error)")
        }
    }

    /// 执行手表发来的请求，返回执行后的状态。
    func handle(_ command: WatchCommand, now: Date = Date()) async -> WatchState {
        guard command.isFresh(now: now) else { return store.watchState(now: now) }
        let live = LiveActivityController.shared
        switch command.action {
        case .clockIn:
            if !live.isWorking {
                do {
                    try await live.startWork(allowWithoutActivity: true)
                } catch {
                    print("[watch] 上班失败：\(error)")
                }
            }
        case .clockOut:
            if live.isWorking { await live.endWork() }
        }
        // startWork / endWork 会发 jisiWorkStateDidChange 推一次；没变化的情况（已经在上班等）这里再推一次
        push()
        return store.watchState()
    }
}

extension PhoneWatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.push() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// 换了一块手表：重新激活，接着推给新手表
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.push() }
    }

    /// 手表在前台、iPhone 可达时：即时请求，回复执行后的状态
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let command = WatchCodec.command(from: message) else {
            replyHandler([:])
            return
        }
        let reply = UncheckedSendable(replyHandler)
        Task { @MainActor in
            let state = await self.handle(command)
            reply.value(WatchCodec.payload(for: state))
        }
    }

    /// iPhone 不可达时手表用 transferUserInfo 排队，送到时执行（太旧的丢掉）
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let command = WatchCodec.command(from: userInfo) else { return }
        Task { @MainActor in _ = await self.handle(command) }
    }
}

/// WatchConnectivity 的回调闭包没标 Sendable，包一层带到主线程用。
private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
