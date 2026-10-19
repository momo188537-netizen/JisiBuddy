import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// 手表上点鸡丝换的表情：脸还是那张照片，只换姿势和小道具。
public enum WatchExpression: String, CaseIterable, Hashable, Sendable {
    /// 平常
    case calm
    /// 冒爱心
    case love
    /// 歪头
    case curious
    /// 叼小鱼干
    case fish
    /// 犯困
    case sleepy

    public var next: WatchExpression {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// 手表 App 和表盘复杂功能用的鸡丝头像（`JisiKit` 里的完整版不编进手表）。
public struct WatchCatFace: View {
    public var expression: WatchExpression
    /// 表盘复杂功能用小图（小组件归档时图片像素不能比小组件本身大）
    public var small: Bool

    public init(expression: WatchExpression = .calm, small: Bool = false) {
        self.expression = expression
        self.small = small
    }

    public var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                face
                    .frame(width: side * 0.9, height: side * 0.9)
                    .rotationEffect(.degrees(tilt), anchor: .bottom)
                    .offset(y: expression == .sleepy ? side * 0.04 : 0)
                    .position(x: side / 2, y: side / 2)
                badge(side: side)
            }
            .frame(width: side, height: side)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("鸡丝")
    }

    var tilt: Double {
        switch expression {
        case .curious: -12
        case .sleepy: 8
        default: 0
        }
    }

    @ViewBuilder
    var face: some View {
        if let image = expression == .sleepy
            ? (small ? WatchArt.closedSmallFace : WatchArt.closedFace)
            : (small ? WatchArt.smallFace : WatchArt.face) {
            image.resizable().scaledToFit()
        } else {
            Circle().fill(WatchArt.furColor)
        }
    }

    @ViewBuilder
    func badge(side: CGFloat) -> some View {
        switch expression {
        case .calm:
            EmptyView()
        case .love:
            Image(systemName: "heart.fill")
                .font(.system(size: side * 0.22))
                .foregroundStyle(.pink)
                .position(x: side * 0.84, y: side * 0.18)
        case .curious:
            Text("?")
                .font(.system(size: side * 0.26, weight: .heavy, design: .rounded))
                .foregroundStyle(.orange)
                .position(x: side * 0.86, y: side * 0.16)
        case .fish:
            if let fish = WatchArt.fish {
                fish.resizable().scaledToFit()
                    .frame(width: side * 0.34, height: side * 0.34)
                    .rotationEffect(.degrees(-20))
                    .position(x: side * 0.5, y: side * 0.86)
            }
        case .sleepy:
            Text("z z")
                .font(.system(size: side * 0.16, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
                .position(x: side * 0.82, y: side * 0.14)
        }
    }
}

/// 头像图片：JisiFace.png 缩出来的手表专用尺寸（scripts/import-jisi.sh 会一起重新生成）。
public enum WatchArt {
    public static let furColor = Color(red: 0.91, green: 0.62, blue: 0.36)

    /// 手表 App 里用，256px
    public static let face: Image? = load("WatchFace")
    /// 表盘复杂功能用，84px
    public static let smallFace: Image? = load("WatchFaceSmall")
    public static let fish: Image? = load("WatchFish")
    /// 闭眼照（犯困表情用），同样两种尺寸
    public static let closedFace: Image? = load("WatchFaceClosed") ?? face
    public static let closedSmallFace: Image? = load("WatchFaceClosedSmall") ?? smallFace

    static func load(_ name: String) -> Image? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
        #if canImport(UIKit)
        return UIImage(contentsOfFile: url.path).map { Image(uiImage: $0) }
        #else
        return NSImage(contentsOf: url).map { Image(nsImage: $0) }
        #endif
    }
}
