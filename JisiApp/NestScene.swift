import JisiKit
import SwiftUI

/// 首页的小窝：固定视角 2D 场景。墙、窗、书桌、地板、已得到的物件，中间是鸡丝。
/// 点物件 → 鸡丝去玩；点鸡丝 → 摸摸。
struct NestScene: View {
    var snapshot: CatSnapshot
    var owned: Set<NestItem>
    var light: SceneLight
    var reactionID: Date?
    var onPet: () -> Void
    var onItem: (NestItem) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                wall
                floor.frame(height: h * 0.3).position(x: w / 2, y: h * 0.85)

                windowView
                    .frame(width: w * 0.3, height: w * 0.3)
                    .position(x: w * 0.2, y: h * 0.24)

                desk(w: w, h: h)

                JisiArt.prop("PropPlant")
                    .frame(width: w * 0.16, height: w * 0.16)
                    .position(x: w * 0.09, y: h * 0.66)
                    .brightness(light == .night ? -0.25 : 0)

                item(.cushion, w: w, h: h, size: CGSize(width: w * 0.3, height: w * 0.1), at: CGPoint(x: w * 0.18, y: h * 0.86)) {
                    CushionView()
                }
                item(.box, w: w, h: h, size: CGSize(width: w * 0.2, height: w * 0.2), at: CGPoint(x: w * 0.86, y: h * 0.83)) {
                    JisiArt.prop("ItemBox")
                }

                let cat = min(w * 0.56, h * 0.58)
                JisiCatView(pose: snapshot.pose, toy: snapshot.toy, animated: true, reactionID: reactionID)
                    .frame(width: cat, height: cat)
                    // 夜里墙是深色，Zzz 之类的次要颜色要用浅色
                    .environment(\.colorScheme, light == .night ? .dark : .light)
                    .position(x: w * 0.5, y: h * 0.88 - cat / 2)
                    .onTapGesture(perform: onPet)

                item(.yarn, w: w, h: h, size: CGSize(width: w * 0.13, height: w * 0.13), at: CGPoint(x: w * 0.27, y: h * 0.93)) {
                    JisiArt.prop("ItemYarn")
                }
            }
        }
        .clipShape(.rect(cornerRadius: 24))
        .animation(.easeInOut(duration: 0.6), value: light)
    }

    /// 物件：拥有且鸡丝没在用时才出现在地上，点了就让鸡丝去玩。
    @ViewBuilder
    func item<V: View>(_ item: NestItem, w: CGFloat, h: CGFloat, size: CGSize, at p: CGPoint, @ViewBuilder _ content: () -> V) -> some View {
        if owned.contains(item) && snapshot.pose != item.pose {
            Button { onItem(item) } label: {
                content().frame(width: size.width, height: size.height)
            }
            .buttonStyle(.plain)
            .position(p)
            .accessibilityLabel("让鸡丝玩\(item.displayName)")
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - 布景

    var wall: some View {
        let colors: [Color] = switch light {
        case .day: [Color(red: 1, green: 0.96, blue: 0.9), Color(red: 1, green: 0.9, blue: 0.78)]
        case .dusk: [Color(red: 1, green: 0.86, blue: 0.72), Color(red: 0.96, green: 0.72, blue: 0.6)]
        case .night: [Color(red: 0.2, green: 0.22, blue: 0.36), Color(red: 0.3, green: 0.28, blue: 0.4)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    var floor: some View {
        let colors: [Color] = light == .night
            ? [Color(red: 0.42, green: 0.32, blue: 0.3), Color(red: 0.32, green: 0.24, blue: 0.24)]
            : [Color(red: 0.93, green: 0.76, blue: 0.58), Color(red: 0.86, green: 0.66, blue: 0.48)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    var windowView: some View {
        ZStack {
            JisiArt.prop("PropWindow")
                .colorMultiply(light == .night ? Color(red: 0.35, green: 0.4, blue: 0.7) : light == .dusk ? Color(red: 1, green: 0.8, blue: 0.7) : .white)
            if light == .night {
                JisiArt.prop("PropMoon").scaleEffect(0.42).offset(x: 14, y: -14)
                JisiArt.prop("PropStar").scaleEffect(0.18).offset(x: -18, y: -20)
            }
        }
    }

    @ViewBuilder
    func desk(w: CGFloat, h: CGFloat) -> some View {
        let wood = Color(red: 0.72, green: 0.5, blue: 0.34)
        let top = h * 0.6
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(wood.opacity(0.85))
                .frame(width: w * 0.03, height: h * 0.2).position(x: w * 0.7, y: top + h * 0.1)
            RoundedRectangle(cornerRadius: 3).fill(wood.opacity(0.85))
                .frame(width: w * 0.03, height: h * 0.2).position(x: w * 0.97, y: top + h * 0.1)
            RoundedRectangle(cornerRadius: 6).fill(wood)
                .frame(width: w * 0.34, height: h * 0.035).position(x: w * 0.84, y: top)
            if snapshot.toy != .laptop {
                JisiArt.prop("PropLaptop").frame(width: w * 0.17, height: w * 0.17)
                    .position(x: w * 0.8, y: top - w * 0.07)
            }
            if snapshot.toy != .coffee {
                JisiArt.prop("PropCoffee").frame(width: w * 0.09, height: w * 0.09)
                    .position(x: w * 0.94, y: top - w * 0.04)
            }
        }
    }
}

/// 地上的软垫（JisiKit 里鸡丝趴着用的同一个样子）
struct CushionView: View {
    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.78, blue: 0.72), Color(red: 0.9, green: 0.58, blue: 0.52)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1.5).padding(5))
            .overlay {
                HStack(spacing: 22) {
                    Circle().frame(width: 5, height: 5)
                    Circle().frame(width: 5, height: 5)
                }
                .foregroundStyle(Color(red: 0.8, green: 0.45, blue: 0.42))
            }
            .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
    }
}
