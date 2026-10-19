import Foundation
import JisiWatchKit
import Observation
import WatchConnectivity
import WidgetKit

/// 手表端：收 iPhone 推来的上班状态，存到手表这边的 App Group 给表盘复杂功能读；
/// 点按钮时先乐观更新，再把请求发给 iPhone（可达就即时发，不可达就排队）。
@MainActor
@Observable
final class WatchModel: NSObject {
    static let shared = WatchModel()

    private(set) var state: WatchState
    var expression: WatchExpression = .calm
    /// 请求已发出、还没等到 iPhone 回复
    private(set) var isSending = false
    /// iPhone 没回复 / 没连上时给一句提示
    private(set) var note: String?

    private let store = WatchStateStore()

    override init() {
        state = store.load() ?? .initial
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func tapCat() {
        expression = expression.next
    }

    /// 手表 App 回到前台时问 iPhone 要一份最新状态（applicationContext 有时要等很久才送到）。
    func requestSync() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(WatchCodec.payload(for: WatchCommand(action: .sync, sentAt: Date())), replyHandler: { reply in
            guard let state = WatchCodec.state(from: reply) else { return }
            Task { @MainActor in self.receive(state) }
        }, errorHandler: nil)
    }

    func send(_ action: WatchCommand.Action, now: Date = Date()) {
        expression = action == .clockIn ? .love : .sleepy
        apply(state.applying(action, at: now))
        note = nil

        let command = WatchCommand(action: action, sentAt: now)
        let payload = WatchCodec.payload(for: command)
        let session = WCSession.default
        guard session.activationState == .activated else {
            session.transferUserInfo(payload)
            note = "等 iPhone 连上后同步"
            return
        }
        guard session.isReachable else {
            session.transferUserInfo(payload)
            note = "iPhone 不在身边，连上后同步"
            return
        }
        isSending = true
        session.sendMessage(payload, replyHandler: { reply in
            let state = WatchCodec.state(from: reply)
            Task { @MainActor in
                self.isSending = false
                // 这是对自己请求的回复，以 iPhone 执行后的结果为准
                if let state { self.receive(state, force: true) }
            }
        }, errorHandler: { _ in
            Task { @MainActor in
                self.isSending = false
                // 即时发送失败就改成排队，iPhone 下次连上时执行
                WCSession.default.transferUserInfo(payload)
                self.note = "iPhone 暂时没回应，连上后同步"
            }
        })
    }

    func receive(_ incoming: WatchState, force: Bool = false) {
        guard force || incoming.shouldReplace(state) else { return }
        // iPhone 那边上班 / 下班了，鸡丝也跟着换个表情
        if incoming.isWorking != state.isWorking { expression = incoming.isWorking ? .love : .sleepy }
        apply(incoming)
        note = nil
    }

    private func apply(_ new: WatchState) {
        let changed = new.isWorking != state.isWorking || new.expectedClockOut != state.expectedClockOut
        state = new
        store.save(new)
        if changed { WidgetCenter.shared.reloadAllTimelines() }
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let state = WatchCodec.state(from: context)
        Task { @MainActor in
            if let state { self.receive(state) }
            self.requestSync()
        }
    }

    /// iPhone 可达时即时推来的状态
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let state = WatchCodec.state(from: message) else { return }
        Task { @MainActor in self.receive(state) }
    }

    /// iPhone 为表盘复杂功能发的 transferCurrentComplicationUserInfo（手表 App 不在前台也会送到）
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let state = WatchCodec.state(from: userInfo) else { return }
        Task { @MainActor in self.receive(state) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.requestSync() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let state = WatchCodec.state(from: applicationContext) else { return }
        Task { @MainActor in self.receive(state) }
    }
}
