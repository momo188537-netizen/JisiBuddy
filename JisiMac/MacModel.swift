import AppKit
import Foundation
import JisiKit
import Observation

/// Mac 菜单栏这头：开着 Bonjour 监听等 iPhone 来连。
///
/// 点按钮先在本地执行（`PeerLocal`，和 iPhone 同一套算法），再放进待发队列；iPhone 连上后发过去，
/// iPhone 执行完回一份状态，Mac 以它为准（后写者为准，见 `PeerMerge`）。iPhone 不在时 Mac 自己也能用。
@MainActor
@Observable
final class MacModel {
    static let shared = MacModel()

    private let store = SharedStore.shared
    private let host = PeerHost()

    private(set) var snapshot: CatSnapshot
    private(set) var session: WorkSession?
    private(set) var meetingUntil: Date?
    private(set) var diary: Diary
    private(set) var schedule: Schedule
    private(set) var lastInteraction: Interaction?
    private(set) var reactionID: Date?
    /// 刚点了「一起下班」，问一句今天累不累（可跳过）
    private(set) var askMood = false
    /// 连着的 iPhone 名字
    private(set) var peerName: String?
    private(set) var lastSync: Date?
    private(set) var now = Date()
    /// 还没被 iPhone 回复的操作（存盘，退出 App 也不丢）
    private(set) var outbox: [PeerCommand] {
        didSet { saveOutbox() }
    }

    var isWorking: Bool { session?.isOpen == true }
    var isConnected: Bool { peerName != nil }
    var listenerError: String? { host.listenerError }
    var isRestDay: Bool { !schedule.isWorkday(now, calendar: .current) }

    private static let outboxKey = "peerOutbox"

    init() {
        snapshot = SharedStore.shared.snapshot()
        session = SharedStore.shared.session
        meetingUntil = SharedStore.shared.meetingUntil
        diary = SharedStore.shared.diary
        schedule = SharedStore.shared.schedule
        lastInteraction = SharedStore.shared.lastInteraction
        outbox = (UserDefaults.standard.data(forKey: Self.outboxKey))
            .flatMap { try? JSONDecoder().decode([PeerCommand].self, from: $0) } ?? []

        host.onMessage = { [weak self] message, _ in self?.receive(message) }
        host.onPeerChange = { [weak self] in
            guard let self else { return }
            if self.host.peer == nil { self.peerName = nil }
        }
        host.start(name: Host.current().localizedName ?? "Mac")

        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                self?.refresh()
            }
        }
    }

    func refresh(now: Date = Date()) {
        self.now = now
        snapshot = store.snapshot(at: now)
        session = store.session
        meetingUntil = store.meetingUntil
        diary = store.diary
        schedule = store.schedule
        lastInteraction = store.lastInteraction
    }

    /// 桌宠此刻的样子（见 `PetBehavior`）
    var petInput: PetBehavior.Input {
        PetBehavior.Input(snapshot: snapshot, session: session, meetingUntil: meetingUntil, lastInteraction: lastInteraction, now: now)
    }

    // MARK: - 操作

    func pet() { react(); send(.pet) }
    func feed() { react(); send(.feed) }
    func play(_ item: NestItem) { send(.play(item)) }
    func clockIn() { send(.clockIn) }

    func clockOut() {
        send(.clockOut)
        askMood = store.preferences.askMoodAtClockOut
    }

    func answerMood(_ mood: ClockOutMood?) {
        askMood = false
        guard let mood else { return }
        react()
        send(.mood(mood))
    }

    func startMeeting(minutes: Int) { send(.startMeeting(minutes: minutes)) }
    func endMeeting() { send(.endMeeting) }

    private func react() { reactionID = Date() }

    private func send(_ action: PeerCommand.Action) {
        let command = PeerCommand(action: action, sentAt: Date())
        PeerLocal.apply(command, to: store)
        outbox.append(command)
        refresh()
        flush()
    }

    /// 把待发的操作发给 iPhone（重连后会再发一遍，iPhone 按 id 去重）
    private func flush() {
        guard isConnected else { return }
        let cutoff = Date().addingTimeInterval(-PeerSync.interactionMaxAge)
        outbox.removeAll { $0.sentAt < cutoff }
        for command in outbox { host.send(.command(command)) }
    }

    private func receive(_ message: PeerMessage) {
        switch message {
        case .hello(let version, let name):
            guard version == PeerSync.version else {
                print("[peer] 协议版本不一致：\(version)")
                return
            }
            peerName = name
            flush()
        case .snapshot(let s):
            lastSync = Date()
            let adopt = PeerMerge.shouldAdopt(s, pending: outbox.map(\.id))
            if let reply = s.replyTo { outbox.removeAll { $0.id == reply } }
            guard adopt else { return }
            store.adopt(s)
            refresh()
        case .command:
            break
        }
    }

    private func saveOutbox() {
        let data = try? JSONEncoder().encode(outbox)
        UserDefaults.standard.set(data, forKey: Self.outboxKey)
    }
}
