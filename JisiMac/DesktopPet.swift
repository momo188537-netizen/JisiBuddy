import AppKit
import JisiKit
import Observation
import SwiftUI

/// 桌宠鸡丝：一直浮在最上面的透明小窗（所有桌面空间都有，不抢焦点）。
///
/// - 只有鸡丝的头那一圈接收鼠标，其他地方的点击直接落到下面的窗口（鼠标移进移出时切换 `ignoresMouseEvents`）
/// - 点一下 = 摸摸；拖动换位置（记住）；右键菜单：喂小鱼干、物件、上下班、开会、隐藏
/// - 样子跟着状态走（`PetBehavior`）：上班醒着陪你、偶尔打哈欠 / 溜达；久了犯困、睡着；下班、开会睡觉
/// - 所有操作走 `MacModel`，和菜单栏、iPhone、手表同一条同步路
@MainActor
final class PetController {
    static let shared = PetController()
    static let visibleKey = "petVisible"
    static let originKey = "petOrigin"

    /// 窗口大小（鸡丝的头 130pt，上面留出跳一下的空间）
    static let size = NSSize(width: 150, height: 170)

    let state = PetState()
    private var panel: PetPanel?
    private var loop: Task<Void, Never>?
    private var monitors: [Any] = []
    private let model = MacModel.shared

    var isVisible: Bool {
        UserDefaults.standard.object(forKey: Self.visibleKey) as? Bool ?? true
    }

    func start() {
        if isVisible { show() }
    }

    func setVisible(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: Self.visibleKey)
        visible ? show() : hide()
    }

    private func show() {
        guard panel == nil else { return }
        let panel = PetPanel(contentRect: NSRect(origin: savedOrigin(), size: Self.size))
        let host = PetHostingView(rootView: AnyView(PetView(state: state).environment(model)))
        host.controller = self
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel
        startTracking()
        startLoop()
    }

    private func hide() {
        loop?.cancel()
        loop = nil
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors = []
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    // MARK: - 位置

    private func savedOrigin() -> NSPoint {
        if let a = UserDefaults.standard.array(forKey: Self.originKey) as? [Double], a.count == 2 {
            let p = NSPoint(x: a[0], y: a[1])
            // 显示器拔掉了之类：存的位置不在任何屏幕上就回到默认位置
            let rect = NSRect(origin: p, size: Self.size).insetBy(dx: 40, dy: 40)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) }) { return p }
        }
        return defaultOrigin()
    }

    /// 默认：主屏幕底部（程序坞上面）靠右
    private func defaultOrigin() -> NSPoint {
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: frame.maxX - Self.size.width - 120, y: frame.minY)
    }

    func saveOrigin() {
        guard let o = panel?.frame.origin else { return }
        UserDefaults.standard.set([Double(o.x), Double(o.y)], forKey: Self.originKey)
    }

    func move(by delta: NSPoint) {
        guard let panel else { return }
        panel.setFrameOrigin(NSPoint(x: panel.frame.origin.x + delta.x, y: panel.frame.origin.y + delta.y))
    }

    // MARK: - 只有头那一圈接鼠标

    /// 鸡丝的头在窗口里的圆（窗口坐标，原点左下）
    static var hitCircle: (center: NSPoint, radius: CGFloat) {
        (NSPoint(x: size.width / 2, y: PetView.catSide * 0.5), PetView.catSide * 0.42)
    }

    func isOverCat(screenPoint p: NSPoint) -> Bool {
        guard let frame = panel?.frame else { return false }
        let c = Self.hitCircle
        let dx = p.x - (frame.minX + c.center.x), dy = p.y - (frame.minY + c.center.y)
        return dx * dx + dy * dy <= c.radius * c.radius
    }

    /// 鼠标移动是事件驱动的（不轮询）：移进头那一圈才接收点击，移出去就让点击穿透
    private func startTracking() {
        panel?.ignoresMouseEvents = !isOverCat(screenPoint: NSEvent.mouseLocation)
        let update: (NSEvent) -> Void = { _ in
            MainActor.assumeIsolated {
                let c = PetController.shared
                guard let panel = c.panel, !c.state.isDragging else { return }
                let over = c.isOverCat(screenPoint: NSEvent.mouseLocation)
                if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
            }
        }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: update) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { update($0); return $0 }) { monitors.append(l) }
    }

    // MARK: - 自己找事做：打哈欠、溜达

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            var nextYawn = Date().addingTimeInterval(.random(in: 180...360))
            var nextWander = Date().addingTimeInterval(.random(in: 240...480))
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, !Task.isCancelled else { return }
                let now = Date()
                guard PetBehavior.isAwake(self.model.petInput), !self.state.isDragging else { continue }
                if now >= nextYawn {
                    nextYawn = now.addingTimeInterval(.random(in: 180...360))
                    self.state.yawn()
                } else if now >= nextWander {
                    nextWander = now.addingTimeInterval(.random(in: 240...480))
                    self.wander()
                }
            }
        }
    }

    /// 跳一下，沿屏幕底部滑到旁边
    func wander() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let x = PetBehavior.wanderX(from: panel.frame.minX, width: panel.frame.width,
                                    minX: visible.minX, maxX: visible.maxX, unit: .random(in: 0...1))
        state.hop()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 1.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(NSPoint(x: x, y: panel.frame.minY))
        } completionHandler: {
            MainActor.assumeIsolated { PetController.shared.saveOrigin() }
        }
    }

    // MARK: - 右键菜单

    func showMenu(with event: NSEvent, in view: NSView) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(PetMenuItem("摸摸") { MacModel.shared.pet() })
        menu.addItem(PetMenuItem("喂小鱼干") { MacModel.shared.feed() })

        let play = NSMenu()
        for item in NestItem.allCases {
            let owned = model.diary.ownedItems.contains(item)
            let entry = PetMenuItem(owned ? item.displayName : "\(item.displayName)（还没有）") { MacModel.shared.play(item) }
            entry.isEnabled = owned
            play.addItem(entry)
        }
        let playItem = NSMenuItem(title: "玩", action: nil, keyEquivalent: "")
        playItem.submenu = play
        menu.addItem(playItem)
        menu.addItem(.separator())

        if model.isWorking {
            menu.addItem(PetMenuItem("一起下班") { MacModel.shared.clockOut() })
        } else {
            menu.addItem(PetMenuItem(model.isRestDay ? "要加班？带鸡丝上班" : "带鸡丝上班") { MacModel.shared.clockIn() })
        }
        if model.meetingUntil != nil {
            menu.addItem(PetMenuItem("开完会了") { MacModel.shared.endMeeting() })
        } else {
            let meeting = NSMenu()
            for m in [30, 60, 90] {
                meeting.addItem(PetMenuItem("\(m) 分钟") { MacModel.shared.startMeeting(minutes: m) })
            }
            let meetingItem = NSMenuItem(title: "我在开会", action: nil, keyEquivalent: "")
            meetingItem.submenu = meeting
            meetingItem.isEnabled = model.isWorking
            menu.addItem(meetingItem)
        }
        menu.addItem(.separator())
        menu.addItem(PetMenuItem("隐藏桌宠") { PetController.shared.setVisible(false) })
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}

/// 桌宠自己的一点动画状态（和数据无关）
@MainActor
@Observable
final class PetState {
    /// 跳一下（溜达开始时）
    private(set) var hopAt: Date?
    /// 打哈欠到什么时候（伸懒腰闭眼的样子）
    private(set) var yawnUntil: Date?
    var isDragging = false

    func hop() { hopAt = Date() }

    func yawn() {
        let until = Date().addingTimeInterval(2.8)
        yawnUntil = until
        Task {
            try? await Task.sleep(for: .seconds(3))
            if self.yawnUntil == until { self.yawnUntil = nil }
        }
    }
}

/// 透明、无边框、不抢焦点、所有桌面空间都在、浮在最上面
final class PetPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 点击 / 拖动 / 右键都在这里处理；SwiftUI 那层只负责画。
final class PetHostingView: NSHostingView<AnyView> {
    weak var controller: PetController?
    private var downAt: NSPoint?
    private var dragged = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        let c = PetController.hitCircle
        let dx = p.x - c.center.x, dy = (isFlipped ? bounds.height - p.y : p.y) - c.center.y
        return dx * dx + dy * dy <= c.radius * c.radius ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        downAt = NSEvent.mouseLocation
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downAt else { return }
        let now = NSEvent.mouseLocation
        if !dragged, hypot(now.x - start.x, now.y - start.y) < 4 { return }
        if !dragged { dragged = true; controller?.state.isDragging = true }
        controller?.move(by: NSPoint(x: now.x - start.x, y: now.y - start.y))
        downAt = now
    }

    override func mouseUp(with event: NSEvent) {
        if dragged {
            controller?.saveOrigin()
            controller?.state.isDragging = false
        } else {
            MacModel.shared.pet()
        }
        downAt = nil
        dragged = false
    }

    override func rightMouseDown(with event: NSEvent) {
        controller?.showMenu(with: event, in: self)
    }
}

/// 带闭包的菜单项
final class PetMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { MainActor.assumeIsolated { handler() } }
}

/// 画鸡丝：头像 + 程序动画（共用 `JisiCatView`），底部对齐窗口。
struct PetView: View {
    static let catSide: CGFloat = 130

    @Environment(MacModel.self) private var model
    let state: PetState

    var body: some View {
        let base = PetBehavior.pose(model.petInput)
        let yawning = state.yawnUntil.map { $0 > Date() } ?? false
        let pose: CatPose = yawning && PetBehavior.isAwake(model.petInput) ? .stretching : base
        let asleep = pose == .sleeping || pose == .drowsy || pose == .cushionNap
        let bounce = [model.reactionID, state.hopAt].compactMap { $0 }.max()

        JisiCatView(pose: pose, toy: model.snapshot.toy, reactionID: bounce,
                    frameInterval: asleep ? 1.0 / 6 : 1.0 / 12)
            .frame(width: Self.catSide, height: Self.catSide)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .animation(.spring(duration: 0.5), value: pose)
            .frame(width: PetController.size.width, height: PetController.size.height, alignment: .bottom)
            .allowsHitTesting(false)
    }
}
