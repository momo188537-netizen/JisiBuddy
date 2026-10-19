import CoreGraphics
import Foundation

/// 一个 CatPose 对应的「图层组合 + 动画参数」。
/// 以后换成全身素材时，只需要改这里的映射和 `JisiCatView` 里的图层，不动状态引擎。
public struct CatLook: Hashable, Sendable {
    // 图层
    public var eyes: EyeState = .open
    public var showToy = false
    public var showZzz = false
    public var showHeart = false
    public var showFish = false

    // 动画参数
    /// 呼吸缩放幅度：0.02 → 0.98–1.02
    public var breatheAmplitude: CGFloat = 0
    /// 呼吸周期（秒）
    public var breathePeriod: Double = 3.2
    /// 是否偶尔眨眼
    public var blinks = false
    /// 歪头幅度（度），左右摆
    public var tiltAmplitude: Double = 0
    /// 固定的歪头 / 低头角度（度），静态画面也用
    public var restingTilt: Double = 0
    /// 头往下垂的距离（相对尺寸的比例）
    public var droop: CGFloat = 0
    /// 进入该状态时弹一下
    public var bounces = false

    public enum EyeState: Hashable, Sendable { case open, half, closed }

    public static func of(_ pose: CatPose) -> CatLook {
        var l = CatLook()
        switch pose {
        case .lounging:
            l.breatheAmplitude = 0.02
            l.blinks = true
        case .playing:
            l.tiltAmplitude = 6
            l.restingTilt = 6
            l.showToy = true
            l.blinks = true
        case .drowsy:
            l.eyes = .half
            l.droop = 0.05
            l.restingTilt = 8
            l.breatheAmplitude = 0.015
            l.breathePeriod = 4.5
        case .sleeping:
            l.eyes = .closed
            l.showZzz = true
            l.droop = 0.03
            l.restingTilt = 4
            l.breatheAmplitude = 0.02
            l.breathePeriod = 5
        case .petted:
            l.eyes = .closed
            l.showHeart = true
            l.bounces = true
        case .fed:
            l.showFish = true
            l.bounces = true
            l.blinks = true
        }
        return l
    }

    /// 眼睛在头像图里的相对位置（0–1）。拿到鸡丝真图后按照片微调。
    public enum FaceGeometry {
        public static let leftEye = CGPoint(x: 0.36, y: 0.50)
        public static let rightEye = CGPoint(x: 0.64, y: 0.50)
        public static let eyeSize = CGSize(width: 0.17, height: 0.10)
    }
}
