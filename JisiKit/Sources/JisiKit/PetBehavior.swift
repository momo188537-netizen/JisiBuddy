import Foundation

/// Mac 桌宠鸡丝此刻摆什么样子、能不能溜达。纯函数，有测试。
///
/// 只有一颗头（睁眼 / 闭眼照），所以「动作」= 换 pose（`CatLook` 决定呼吸、眨眼、歪头、闭眼）
/// + 窗口在屏幕底部滑到新位置、跳一下。
public enum PetBehavior {
    /// 上班后多久没理它开始犯困（半闭眼点头）
    public static let drowsyAfter: TimeInterval = 40 * 60
    /// 再过多久睡着（闭眼 + Zzz）
    public static let dozeAfter: TimeInterval = 75 * 60

    public struct Input: Sendable {
        public var snapshot: CatSnapshot
        public var session: WorkSession?
        public var meetingUntil: Date?
        public var lastInteraction: Interaction?
        public var now: Date

        public init(snapshot: CatSnapshot, session: WorkSession?, meetingUntil: Date?, lastInteraction: Interaction?, now: Date) {
            self.snapshot = snapshot
            self.session = session
            self.meetingUntil = meetingUntil
            self.lastInteraction = lastInteraction
            self.now = now
        }

        var isWorking: Bool { session?.isOpen == true }
        var inMeeting: Bool { meetingUntil.map { $0 > now } ?? false }

        /// 刚摸过 / 喂过 / 在玩物件（CatBrain 的互动反应还没过期）
        var isReacting: Bool {
            guard let i = lastInteraction else { return false }
            return now >= i.date && now < i.date.addingTimeInterval(CatBrain.duration(of: i.kind))
        }
    }

    public static func pose(_ input: Input) -> CatPose {
        // 互动反应优先：摸摸、喂食、毛线球、纸箱、软垫
        if input.isReacting { return input.snapshot.pose }
        // 开会：安静睡觉；下班 / 还没上班：睡觉
        if input.inMeeting || !input.isWorking { return .sleeping }
        let idle = input.now.timeIntervalSince(lastActive(input))
        if idle >= dozeAfter { return .sleeping }
        if idle >= drowsyAfter { return .drowsy }
        switch input.snapshot.pose {
        // 上班时间 CatBrain 偶尔会给出睡觉 / 软垫打盹，桌宠这时还是醒着陪你
        case .sleeping, .cushionNap: return .lounging
        default: return input.snapshot.pose
        }
    }

    /// 能不能溜达到别处 / 打哈欠：上班、醒着、没在开会、没在互动。
    public static func isAwake(_ input: Input) -> Bool {
        guard input.isWorking, !input.inMeeting, !input.isReacting else { return false }
        switch pose(input) {
        case .sleeping, .drowsy, .cushionNap: return false
        default: return true
        }
    }

    /// 上次「有人理它」的时间：上班或最近一次互动
    static func lastActive(_ input: Input) -> Date {
        var t = input.session?.startedAt ?? input.now
        if let i = input.lastInteraction, i.date > t { t = i.date }
        return t
    }

    /// 溜达：在屏幕底部左右滑一段，不出屏幕。`unit` 是 0...1 的随机数。
    public static func wanderX(from x: Double, width: Double, minX: Double, maxX: Double, unit: Double) -> Double {
        let lo = minX, hi = max(minX, maxX - width)
        // 80～220pt，左右各一半概率；碰到边就往回走
        let distance = 80 + 140 * abs(unit * 2 - 1)
        var target = x + (unit < 0.5 ? -distance : distance)
        if target < lo || target > hi { target = x + (unit < 0.5 ? distance : -distance) }
        return min(hi, max(lo, target))
    }
}
