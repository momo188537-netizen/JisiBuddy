import Foundation
import Network

/// 一条 TCP 连接，收发 `PeerMessage`（长度前缀帧）。回调都在主线程。
public final class PeerConnection: @unchecked Sendable {
    public let connection: NWConnection
    public var onMessage: (@MainActor (PeerMessage) -> Void)?
    public var onReady: (@MainActor () -> Void)?
    /// 断开（失败或对方关了）；只回调一次
    public var onClose: (@MainActor () -> Void)?
    private var closed = false

    public init(_ connection: NWConnection) {
        self.connection = connection
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Task { @MainActor in self.onReady?() }
                self.receiveHeader()
            case .failed, .cancelled:
                self.finish()
            case .waiting:
                // 对方不在了（比如 iPhone 退后台），不等了，让上层重新找
                self.cancel()
            default:
                break
            }
        }
        connection.start(queue: .main)
    }

    public func send(_ message: PeerMessage) {
        guard let data = PeerCodec.frame(message) else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error != nil { self?.cancel() }
        })
    }

    public func cancel() {
        connection.cancel()
        finish()
    }

    private func finish() {
        guard !closed else { return }
        closed = true
        Task { @MainActor in self.onClose?() }
    }

    private func receiveHeader() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self else { return }
            guard error == nil, let data, let length = PeerCodec.bodyLength(data) else {
                self.cancel()
                return
            }
            self.receiveBody(length)
        }
    }

    private func receiveBody(_ length: Int) {
        guard length > 0 else { receiveHeader(); return }
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, error in
            guard let self else { return }
            guard error == nil, let data, data.count == length else { self.cancel(); return }
            if let message = PeerCodec.decode(data) {
                Task { @MainActor in self.onMessage?(message) }
            }
            self.receiveHeader()
        }
    }
}

extension NWParameters {
    /// 局域网 TCP，开 keepalive，iPhone 走开后能较快发现断了
    static var jisiPeer: NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.keepaliveInterval = 5
        tcp.keepaliveCount = 3
        tcp.noDelay = true
        let p = NWParameters(tls: nil, tcp: tcp)
        p.includePeerToPeer = true
        return p
    }
}

/// Mac：一直开着 Bonjour 监听，等 iPhone 来连。同一时间只留最新的一条连接。
@MainActor
public final class PeerHost {
    public private(set) var peer: PeerConnection?
    public var onMessage: ((PeerMessage, PeerConnection) -> Void)?
    public var onPeerChange: (() -> Void)?
    /// 监听失败（比如本地网络权限被拒）
    public private(set) var listenerError: String?

    private var listener: NWListener?
    private var retry: Task<Void, Never>?

    public init() {}

    public func start(name: String) {
        guard listener == nil else { return }
        do {
            let l = try NWListener(using: .jisiPeer)
            l.service = NWListener.Service(name: name, type: PeerSync.serviceType)
            l.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            l.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.listenerError = nil
                    case .failed(let error):
                        self?.listenerError = "\(error)"
                        self?.restart(name: name)
                    case .waiting(let error):
                        self?.listenerError = "\(error)"
                    default:
                        break
                    }
                    self?.onPeerChange?()
                }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            listenerError = "\(error)"
            restart(name: name)
        }
    }

    private func restart(name: String) {
        listener?.cancel()
        listener = nil
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.start(name: name)
        }
    }

    private func accept(_ connection: NWConnection) {
        peer?.cancel()
        let p = PeerConnection(connection)
        p.onMessage = { [weak self, weak p] message in
            guard let self, let p else { return }
            self.onMessage?(message, p)
        }
        p.onReady = { [weak self] in self?.onPeerChange?() }
        p.onClose = { [weak self, weak p] in
            guard let self, self.peer === p else { return }
            self.peer = nil
            self.onPeerChange?()
        }
        peer = p
        p.start()
    }

    public func send(_ message: PeerMessage) {
        peer?.send(message)
    }
}

/// iPhone：在局域网里找 Mac 的服务，找到就连；断了重新找。App 在前台时运行。
@MainActor
public final class PeerClient {
    public private(set) var peer: PeerConnection?
    public private(set) var isConnected = false
    public var onMessage: ((PeerMessage) -> Void)?
    public var onConnect: (() -> Void)?

    private var browser: NWBrowser?
    private var running = false

    public init() {}

    public func start() {
        guard !running else { return }
        running = true
        browse()
    }

    public func stop() {
        running = false
        browser?.cancel()
        browser = nil
        peer?.cancel()
        peer = nil
        isConnected = false
    }

    private func browse() {
        guard running, browser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: PeerSync.serviceType, domain: nil), using: .jisiPeer)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.found(results) }
        }
        b.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                Task { @MainActor in
                    self?.browser?.cancel()
                    self?.browser = nil
                    try? await Task.sleep(for: .seconds(5))
                    self?.browse()
                }
            }
        }
        b.start(queue: .main)
        browser = b
    }

    private func found(_ results: Set<NWBrowser.Result>) {
        guard running, peer == nil, let result = results.first else { return }
        let p = PeerConnection(NWConnection(to: result.endpoint, using: .jisiPeer))
        p.onReady = { [weak self] in
            self?.isConnected = true
            self?.onConnect?()
        }
        p.onMessage = { [weak self] in self?.onMessage?($0) }
        p.onClose = { [weak self, weak p] in
            guard let self, self.peer === p else { return }
            self.peer = nil
            self.isConnected = false
            // 重新找一遍（Mac 可能换了地址，或者刚重启）
            self.browser?.cancel()
            self.browser = nil
            Task {
                try? await Task.sleep(for: .seconds(2))
                self.browse()
            }
        }
        peer = p
        p.start()
    }

    public func send(_ message: PeerMessage) {
        guard isConnected else { return }
        peer?.send(message)
    }
}
