import AppKit
import JisiKit
import SwiftUI

/// Mac 菜单栏里的鸡丝：点菜单栏上的头像打开小窗。和 iPhone 在同一个 Wi-Fi 下自动同步（见 `MacModel`）。
@main
struct JisiMacApp: App {
    @State private var model = MacModel.shared

    init() {
        #if DEBUG
        // 调试：`鸡丝 --render-menu out.png` 把菜单栏小窗画成图片后退出（不用点菜单栏也能看界面）
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-menu"), i + 1 < args.count {
            MainActor.assumeIsolated { MenuSnapshot.write(to: URL(fileURLWithPath: args[i + 1])) }
            exit(0)
        }
        // `鸡丝 --render-pet out.png`：桌宠的样子（醒着、睡着各一张拼在一起）
        if let i = args.firstIndex(of: "--render-pet"), i + 1 < args.count {
            MainActor.assumeIsolated { MenuSnapshot.writePet(to: URL(fileURLWithPath: args[i + 1])) }
            exit(0)
        }
        #endif
        // 等 App 启动完再开桌宠窗口
        DispatchQueue.main.async { PetController.shared.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(model)
                .tint(.orange)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 菜单栏上的头像（睡觉 / 打盹时换闭眼照），上班时旁边显示离下班还有多久。
struct MenuBarLabel: View {
    let model: MacModel

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarIcon.image(closed: MenuBarIcon.eyesClosed(model.snapshot.pose)))
            if let text = remaining { Text(text).monospacedDigit() }
        }
    }

    private var remaining: String? {
        guard let s = model.session, s.isOpen else { return nil }
        let left = s.expectedClockOut.timeIntervalSince(model.now)
        guard left > 0 else { return "该下班啦" }
        let minutes = Int(left / 60)
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

enum MenuBarIcon {
    static func eyesClosed(_ pose: CatPose) -> Bool {
        switch CatLook.of(pose).eyes {
        case .closed, .half: true
        case .open: false
        }
    }

    private static let open = make(JisiArt.faceURL)
    private static let closed = make(JisiArt.closedFaceURL)

    static func image(closed isClosed: Bool) -> NSImage {
        (isClosed ? closed : open) ?? NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "鸡丝")!
    }

    private static func make(_ url: URL?) -> NSImage? {
        guard let url, let source = NSImage(contentsOf: url) else { return nil }
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "鸡丝"
        return image
    }
}

#if DEBUG
@MainActor
enum MenuSnapshot {
    static func write(to url: URL) {
        save(MenuView().environment(MacModel.shared).tint(.orange), to: url)
    }

    static func writePet(to url: URL) {
        let poses: [CatPose] = [.working, .stretching, .drowsy, .sleeping, .petted]
        let view = HStack(spacing: 0) {
            ForEach(poses, id: \.self) { pose in
                VStack {
                    JisiCatView(pose: pose, animated: false)
                        .frame(width: PetView.catSide, height: PetView.catSide)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                        .frame(width: PetController.size.width, height: PetController.size.height, alignment: .bottom)
                    Text(pose.displayName).font(.caption)
                }
            }
        }
        .padding()
        .background(Color(white: 0.85))
        save(view, to: url)
    }

    static func save(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
