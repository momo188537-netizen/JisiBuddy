import SwiftUI
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

    public init(pose: CatPose, toy: Toy? = nil, animated: Bool = true, reactionID: Date? = nil) {
        self.pose = pose
        self.toy = toy
        self.animated = animated
        self.reactionID = reactionID
    }

    public var body: some View {
        let look = CatLook.of(pose)
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            Group {
                if animated {
                    TimelineView(.animation) { context in
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
        let tilt: Double = {
            guard let t else { return look.restingTilt }
            if look.tiltAmplitude > 0 { return look.tiltAmplitude * sin(2 * .pi * t / 2.6) }
            // 困了：慢慢点头
            if look.droop > 0 { return look.restingTilt + 3 * sin(2 * .pi * t / 6) }
            return look.restingTilt
        }()
        let eyes: CatLook.EyeState = {
            guard let t, look.blinks, look.eyes == .open else { return look.eyes }
            // 大约每 4.7 秒眨一次，每次 0.15 秒
            return t.truncatingRemainder(dividingBy: 4.7) < 0.15 ? .closed : .open
        }()

        ZStack {
            head(eyes: eyes, side: side)
                .scaleEffect(breathe, anchor: .bottom)
                .rotationEffect(.degrees(tilt), anchor: .bottom)
                .offset(y: look.droop * side)

            if look.showToy {
                Image(systemName: (toy ?? .yarn).symbolName)
                    .font(.system(size: side * 0.22, weight: .semibold))
                    .foregroundStyle(.tint)
                    .position(x: side * 0.86, y: side * 0.84)
            }
            if look.showFish {
                Image(systemName: "fish.fill")
                    .font(.system(size: side * 0.2))
                    .foregroundStyle(.orange)
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

    func head(eyes: CatLook.EyeState, side: CGFloat) -> some View {
        ZStack {
            if let image = JisiArt.face {
                image.resizable().scaledToFit()
            } else {
                PlaceholderFace()
            }
            EyePatches(state: eyes)
        }
        .frame(width: side * 0.86, height: side * 0.86)
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
    public static let face: Image? = {
        guard let url = Bundle.module.url(forResource: "JisiFace", withExtension: "png") else { return nil }
        #if canImport(UIKit)
        return UIImage(contentsOfFile: url.path).map { Image(uiImage: $0) }
        #else
        return NSImage(contentsOf: url).map { Image(nsImage: $0) }
        #endif
    }()
}
