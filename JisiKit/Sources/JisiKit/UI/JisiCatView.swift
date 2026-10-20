import ImageIO
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// 鸡丝本体：一张正面头像 + 程序动画。App、锁屏 Widget、Live Activity 共用。
///
/// - `animated == false` 时画出该 pose 的代表性静帧（Widget / Live Activity 不跑连续动画）。
/// - `reactionID` 变化时触发「弹一下」。
public struct JisiCatView: View {
    public var pose: CatPose
    public var toy: Toy?
    public var animated: Bool
    public var reactionID: Date?
    /// 静帧用较大的图（主屏幕小组件）；锁屏小组件、Live Activity 用默认的小图。
    public var largeStill: Bool
    /// 锁屏小组件的单色（vibrant）模式：用高对比度灰度头像，五官更清楚。
    public var monochrome: Bool
    /// 动画最快多久画一帧（秒）。nil = 跟屏幕刷新走；一直开着的桌宠用 1/15 秒省电。
    public var frameInterval: Double?

    public init(pose: CatPose, toy: Toy? = nil, animated: Bool = true, reactionID: Date? = nil, largeStill: Bool = false,
                monochrome: Bool = false, frameInterval: Double? = nil) {
        self.pose = pose
        self.toy = toy
        self.animated = animated
        self.reactionID = reactionID
        self.largeStill = largeStill
        self.monochrome = monochrome
        self.frameInterval = frameInterval
    }

    public var body: some View {
        let look = CatLook.of(pose)
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            Group {
                if animated {
                    TimelineView(.animation(minimumInterval: frameInterval, paused: false)) { context in
                        frame(look: look, side: side, t: context.date.timeIntervalSinceReferenceDate)
                    }
                } else {
                    frame(look: look, side: side, t: nil)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .keyframeAnimator(initialValue: Bounce(), trigger: reactionID) { content, b in
            content
                .scaleEffect(x: b.squash, y: 2 - b.squash, anchor: .bottom)
                .offset(y: b.lift)
        } keyframes: { _ in
            KeyframeTrack(\.lift) {
                SpringKeyframe(-14, duration: 0.18)
                SpringKeyframe(0, duration: 0.35, spring: .bouncy)
            }
            KeyframeTrack(\.squash) {
                LinearKeyframe(1.06, duration: 0.08)
                SpringKeyframe(0.96, duration: 0.15)
                SpringKeyframe(1, duration: 0.3, spring: .bouncy)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("鸡丝，\(pose.displayName)")
    }

    struct Bounce {
        var lift: CGFloat = 0
        var squash: CGFloat = 1
    }

    // MARK: - 单帧

    @ViewBuilder
    func frame(look: CatLook, side: CGFloat, t: Double?) -> some View {
        let breathe: CGFloat = {
            guard let t, look.breatheAmplitude > 0 else { return 1 }
            return 1 + look.breatheAmplitude * CGFloat(sin(2 * .pi * t / look.breathePeriod))
        }()
        let stretch: CGFloat = {
            guard look.stretchAmplitude > 0 else { return 1 }
            guard let t else { return 1 + look.stretchAmplitude * 0.8 }
            // 慢慢拉长再缩回
            return 1 + look.stretchAmplitude * CGFloat(max(0, sin(2 * .pi * t / 3)))
        }()
        let tilt: Double = {
            guard let t else { return look.restingTilt }
            if look.tiltAmplitude > 0 { return look.restingTilt + look.tiltAmplitude * sin(2 * .pi * t / look.tiltPeriod) }
            // 困了：慢慢点头
            if look.droop > 0 { return look.restingTilt + 3 * sin(2 * .pi * t / 6) }
            return look.restingTilt
        }()
        let eyes: CatLook.EyeState = {
            guard let t, look.blinks, look.eyes == .open else { return look.eyes }
            // 大约每 4.7 秒眨一次，每次 0.15 秒
            return t.truncatingRemainder(dividingBy: 4.7) < 0.15 ? .closed : .open
        }()
        let laptopInFront = toy == .laptop && (pose == .working || pose == .drowsy || pose == .sleeping)

        ZStack {
            if look.onCushion {
                Cushion()
                    .frame(width: side * 0.98, height: side * 0.3)
                    .position(x: side * 0.5, y: side * 0.86)
            }

            head(eyes: eyes, side: side, small: t == nil)
                .scaleEffect(look.headScale, anchor: .bottom)
                .scaleEffect(x: 1, y: stretch, anchor: .bottom)
                .scaleEffect(breathe, anchor: .bottom)
                .rotationEffect(.degrees(tilt), anchor: .bottom)
                .offset(y: look.droop * side)

            if look.inBox {
                JisiArt.prop(Toy.box.assetName, small: t == nil)
                    .frame(width: side * 0.66, height: side * 0.66)
                    .position(x: side * 0.5, y: side * 0.86)
            } else if look.batting {
                let roll = t.map { sin(2 * .pi * $0 / look.tiltPeriod) } ?? 0.6
                JisiArt.prop(Toy.yarn.assetName, small: t == nil)
                    .frame(width: side * 0.3, height: side * 0.3)
                    .rotationEffect(.degrees(roll * 40))
                    .position(x: side * (0.78 + 0.08 * roll), y: side * 0.84)
            } else if laptopInFront {
                JisiArt.prop(Toy.laptop.assetName, small: t == nil)
                    .frame(width: side * 0.6, height: side * 0.6)
                    .position(x: side * 0.5, y: side * 0.86)
            } else if look.showToy, let toy {
                JisiArt.prop(toy.assetName, small: t == nil)
                    .frame(width: side * 0.3, height: side * 0.3)
                    .position(x: side * 0.84, y: side * 0.82)
            }
            if look.showFish {
                JisiArt.prop("PropFish", small: t == nil)
                    .frame(width: side * 0.26, height: side * 0.26)
                    .rotationEffect(.degrees(-20))
                    .position(x: side * 0.5, y: side * 0.88)
            }
            if look.showHeart {
                floating(t: t, period: 1.6, side: side) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: side * 0.16))
                        .foregroundStyle(.pink)
                }
                .position(x: side * 0.82, y: side * 0.2)
            }
            if look.showZzz {
                zzz(t: t, side: side)
                    .position(x: side * 0.82, y: side * 0.18)
            }
        }
        .frame(width: side, height: side)
    }

    /// 闭眼（睡觉、打盹、眨眼、犯困）整张换成鸡丝的闭眼照，两张照片构图对齐，直接切换。
    func head(eyes: CatLook.EyeState, side: CGFloat, small: Bool) -> some View {
        ZStack {
            if let image = artwork(small: small, closed: eyes != .open) {
                fullColor(image.resizable()).scaledToFit()
            } else {
                PlaceholderFace()
                EyePatches(state: eyes)
            }
        }
        .frame(width: side * 0.86, height: side * 0.86)
    }

    func artwork(small: Bool, closed: Bool) -> Image? {
        let art = closed ? JisiArt.closed : JisiArt.open
        if !small { return art.face }
        if monochrome { return art.monoFace ?? art.smallFace }
        return largeStill ? art.mediumFace : art.smallFace
    }

    /// 系统给 Widget 着色（accented 模式）时，头像保持原色。
    @ViewBuilder
    func fullColor(_ image: Image) -> some View {
        #if canImport(WidgetKit) && os(iOS)
        if #available(iOS 18.0, *) {
            image.widgetAccentedRenderingMode(.fullColor)
        } else {
            image
        }
        #else
        image
        #endif
    }

    func floating<V: View>(t: Double?, period: Double, side: CGFloat, @ViewBuilder _ content: () -> V) -> some View {
        let phase = t.map { $0.truncatingRemainder(dividingBy: period) / period } ?? 0.4
        return content()
            .offset(y: -CGFloat(phase) * side * 0.15)
            .opacity(1 - phase * 0.8)
    }

    func zzz(t: Double?, side: CGFloat) -> some View {
        ZStack {
            ForEach(0..<3) { i in
                let phase = t.map { ($0 / 3 + Double(i) / 3).truncatingRemainder(dividingBy: 1) } ?? Double(i) / 3
                Text("z")
                    .font(.system(size: side * (0.09 + 0.04 * CGFloat(phase)), weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                    .offset(x: CGFloat(phase) * side * 0.1, y: -CGFloat(phase) * side * 0.18)
                    .opacity(t == nil ? 1 : 1 - phase)
            }
        }
    }
}

/// 眨眼 / 闭眼贴片。先用简单形状占位：一块毛色的椭圆盖住眼睛，上面画一条弧线。
/// 只在没有鸡丝照片、用占位脸时用：代码画的眼皮。
struct EyePatches: View {
    var state: CatLook.EyeState

    var body: some View {
        GeometryReader { geo in
            if state != .open {
                let g = CatLook.FaceGeometry.self
                ForEach([g.leftEye, g.rightEye], id: \.x) { p in
                    EyeLid(half: state == .half)
                        .frame(width: g.eyeSize.width * geo.size.width, height: g.eyeSize.height * geo.size.height)
                        .position(x: p.x * geo.size.width, y: p.y * geo.size.height)
                }
            }
        }
    }
}

struct EyeLid: View {
    var half: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .top) {
                Ellipse()
                    .fill(JisiArt.furColor)
                    .frame(height: half ? h * 0.6 : h)
                Path { p in
                    let y = half ? h * 0.55 : h * 0.5
                    p.move(to: CGPoint(x: w * 0.1, y: y))
                    p.addQuadCurve(to: CGPoint(x: w * 0.9, y: y), control: CGPoint(x: w * 0.5, y: y + h * 0.35))
                }
                .stroke(Color(red: 0.25, green: 0.15, blue: 0.1), style: StrokeStyle(lineWidth: max(1, h * 0.14), lineCap: .round))
            }
        }
    }
}

/// 没有鸡丝照片时的占位头像：橘色圆脸 + 耳朵 + 眼睛。眼睛位置与 FaceGeometry 一致，方便对齐贴片。
struct PlaceholderFace: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let g = CatLook.FaceGeometry.self
            ZStack {
                Ear().fill(JisiArt.furColor).frame(width: w * 0.3, height: w * 0.3).position(x: w * 0.24, y: w * 0.2)
                Ear().fill(JisiArt.furColor).frame(width: w * 0.3, height: w * 0.3).position(x: w * 0.76, y: w * 0.2)
                Ellipse().fill(JisiArt.furColor).frame(width: w * 0.86, height: w * 0.72).position(x: w * 0.5, y: w * 0.56)
                Ellipse().fill(Color.white.opacity(0.85)).frame(width: w * 0.36, height: w * 0.24).position(x: w * 0.5, y: w * 0.7)
                ForEach([g.leftEye, g.rightEye], id: \.x) { p in
                    Capsule().fill(Color(red: 0.25, green: 0.15, blue: 0.1))
                        .frame(width: w * 0.07, height: w * 0.09)
                        .position(x: p.x * w, y: p.y * w)
                }
                Image(systemName: "triangle.fill")
                    .rotationEffect(.degrees(180))
                    .font(.system(size: w * 0.06))
                    .foregroundStyle(.pink)
                    .position(x: w * 0.5, y: w * 0.62)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 软垫：SwiftUI 画的，暖粉色、有两颗纽扣。
struct Cushion: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Capsule()
                    .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.78, blue: 0.72), Color(red: 0.9, green: 0.58, blue: 0.52)],
                                         startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.12), radius: h * 0.08, y: h * 0.06)
                Capsule()
                    .stroke(Color.white.opacity(0.5), lineWidth: max(1, h * 0.04))
                    .padding(h * 0.12)
                ForEach([0.36, 0.64], id: \.self) { x in
                    Circle()
                        .fill(Color(red: 0.8, green: 0.45, blue: 0.42))
                        .frame(width: h * 0.12, height: h * 0.12)
                        .position(x: w * x, y: h * 0.5)
                }
            }
        }
    }
}

struct Ear: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

public enum JisiArt {
    public static let furColor = Color(red: 0.91, green: 0.62, blue: 0.36)

    /// JisiKit/Sources/JisiKit/Resources/JisiFace.png（已水平翻转、缩到 512px）。
    public static let face: Image? = load(maxPixel: nil)

    /// 同一套尺寸的一组头像（睁眼 / 闭眼各一组）。
    public struct FaceSet: Sendable {
        public let face: Image?
        public let mediumFace: Image?
        public let smallFace: Image?
        public let monoFace: Image?
    }

    public static let open = FaceSet(face: face, mediumFace: mediumFace, smallFace: smallFace, monoFace: monoFace)

    /// 闭眼照 JisiFaceClosed.png（用户提供，scripts/whiteout.swift 去白底，见 Art/CREDITS.md）。
    public static let closed = FaceSet(
        face: load(name: "JisiFaceClosed", maxPixel: nil) ?? face,
        mediumFace: load(name: "JisiFaceClosed", maxPixel: 320) ?? mediumFace,
        smallFace: load(name: "JisiFaceClosed", maxPixel: smallFacePixels) ?? smallFace,
        monoFace: loadPlain("JisiFaceClosedMono") ?? monoFace
    )

    /// 小物件图片（Microsoft Fluent Emoji，见 Art/CREDITS.md）。`small` 用于 Widget / Live Activity。
    @ViewBuilder
    public static func prop(_ name: String, small: Bool = false) -> some View {
        if let image = propImage(name, small: small) {
            image.resizable().scaledToFit()
        } else {
            Color.clear
        }
    }

    static func propImage(_ name: String, small: Bool) -> Image? {
        let key = small ? name + "@small" : name
        propLock.lock(); defer { propLock.unlock() }
        if let cached = propCache[key] { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
        let image: Image?
        if small {
            image = thumbnail(url: url, maxPixel: 96).map { cg in
                #if canImport(UIKit)
                Image(uiImage: UIImage(cgImage: cg))
                #else
                Image(nsImage: NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height)))
                #endif
            }
        } else {
            #if canImport(UIKit)
            image = UIImage(contentsOfFile: url.path).map { Image(uiImage: $0) }
            #else
            image = NSImage(contentsOf: url).map { Image(nsImage: $0) }
            #endif
        }
        propCache[key] = image
        return image
    }

    nonisolated(unsafe) static var propCache: [String: Image?] = [:]
    static let propLock = NSLock()

    /// 静帧用的小图（锁屏 Widget、Live Activity）。Widget 归档时图片像素面积不能超过 Widget 本身，
    /// 512px 原图放进圆形 / 长方形锁屏 Widget 会渲染失败，只剩灰色占位。
    public static let smallFace: Image? = load(maxPixel: smallFacePixels)
    static let smallFacePixels = 144

    /// 锁屏单色模式用：scripts/mono-face.swift 生成的 144px 高对比度灰度图。
    public static let monoFace: Image? = loadPlain("JisiFaceMono")

    static func loadPlain(_ name: String) -> Image? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
        #if canImport(UIKit)
        return UIImage(contentsOfFile: url.path).map { Image(uiImage: $0) }
        #else
        return NSImage(contentsOf: url).map { Image(nsImage: $0) }
        #endif
    }

    /// 主屏幕 / 待机小组件用。
    public static let mediumFace: Image? = load(maxPixel: 320)

    public static var faceURL: URL? { Bundle.module.url(forResource: "JisiFace", withExtension: "png") }

    public static var closedFaceURL: URL? { Bundle.module.url(forResource: "JisiFaceClosed", withExtension: "png") }

    static func load(name: String = "JisiFace", maxPixel: Int?) -> Image? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
        guard let maxPixel else {
            #if canImport(UIKit)
            return UIImage(contentsOfFile: url.path).map { Image(uiImage: $0) }
            #else
            return NSImage(contentsOf: url).map { Image(nsImage: $0) }
            #endif
        }
        guard let cg = thumbnail(url: url, maxPixel: maxPixel) else { return nil }
        #if canImport(UIKit)
        return Image(uiImage: UIImage(cgImage: cg))
        #else
        return Image(nsImage: NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height)))
        #endif
    }

    static func thumbnail(url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
