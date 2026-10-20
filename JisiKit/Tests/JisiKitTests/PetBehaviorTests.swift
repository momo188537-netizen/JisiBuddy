import Foundation
import Testing
@testable import JisiKit

struct PetBehaviorTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func input(pose: CatPose = .working, working: Bool = true, startedAgo: TimeInterval = 600,
               meeting: Bool = false, interaction: Interaction? = nil) -> PetBehavior.Input {
        let session = working ? WorkSession(startedAt: now.addingTimeInterval(-startedAgo), expectedClockOut: now.addingTimeInterval(3600)) : nil
        return .init(snapshot: CatSnapshot(pose: pose, line: "", date: now), session: session,
                     meetingUntil: meeting ? now.addingTimeInterval(1800) : nil, lastInteraction: interaction, now: now)
    }

    @Test func offWorkAndMeetingSleep() {
        #expect(PetBehavior.pose(input(working: false)) == .sleeping)
        #expect(PetBehavior.pose(input(meeting: true)) == .sleeping)
        #expect(!PetBehavior.isAwake(input(working: false)))
        #expect(!PetBehavior.isAwake(input(meeting: true)))
    }

    @Test func atWorkStaysAwakeThenDozes() {
        #expect(PetBehavior.pose(input()) == .working)
        #expect(PetBehavior.isAwake(input()))
        // 上班时间 CatBrain 给的睡觉，桌宠改成醒着陪你
        #expect(PetBehavior.pose(input(pose: .sleeping)) == .lounging)
        #expect(PetBehavior.pose(input(startedAgo: PetBehavior.drowsyAfter + 1)) == .drowsy)
        #expect(PetBehavior.pose(input(startedAgo: PetBehavior.dozeAfter + 1)) == .sleeping)
        #expect(!PetBehavior.isAwake(input(startedAgo: PetBehavior.dozeAfter + 1)))
    }

    @Test func interactionWakesAndReacts() {
        let pet = Interaction(kind: .pet, date: now.addingTimeInterval(-30))
        // 刚摸过：显示反应，哪怕下班了
        #expect(PetBehavior.pose(input(pose: .petted, working: false, interaction: pet)) == .petted)
        // 摸过之后重新计时，不犯困
        let old = Interaction(kind: .pet, date: now.addingTimeInterval(-600))
        #expect(PetBehavior.pose(input(startedAgo: PetBehavior.dozeAfter + 1, interaction: old)) == .working)
    }

    @Test func wanderStaysOnScreen() {
        for u in stride(from: 0.0, through: 1.0, by: 0.05) {
            let x = PetBehavior.wanderX(from: 10, width: 150, minX: 0, maxX: 1440, unit: u)
            #expect(x >= 0 && x <= 1290)
            #expect(abs(x - 10) >= 80 || x == 0)
            let y = PetBehavior.wanderX(from: 1280, width: 150, minX: 0, maxX: 1440, unit: u)
            #expect(y >= 0 && y <= 1290)
        }
    }
}

struct PetClampTests {
    let size = CGSize(width: 150, height: 170)
    // 1512×982 的屏幕：菜单栏 33pt，程序坞在下面 60pt
    let visible = CGRect(x: 0, y: 60, width: 1512, height: 889)

    @Test func insideStaysPut() {
        #expect(PetBehavior.clamp(origin: CGPoint(x: 600, y: 300), size: size, into: visible) == CGPoint(x: 600, y: 300))
    }

    @Test func pulledBackFromEveryEdge() {
        // 拖出下边、左边、右边、上边
        #expect(PetBehavior.clamp(origin: CGPoint(x: 600, y: -80), size: size, into: visible) == CGPoint(x: 600, y: 60))
        #expect(PetBehavior.clamp(origin: CGPoint(x: -70, y: 300), size: size, into: visible) == CGPoint(x: 0, y: 300))
        #expect(PetBehavior.clamp(origin: CGPoint(x: 1450, y: 300), size: size, into: visible) == CGPoint(x: 1362, y: 300))
        #expect(PetBehavior.clamp(origin: CGPoint(x: 600, y: 900), size: size, into: visible) == CGPoint(x: 600, y: 779))
    }

    @Test func headReachesMenuBar() {
        // 窗口里鸡丝画在下面 130×130、左右各空 10pt，上面 40pt 是跳一下用的透明空间
        let content = CGRect(x: 10, y: 0, width: 130, height: 130)
        let top = PetBehavior.clamp(origin: CGPoint(x: 600, y: 2000), size: size, content: content, into: visible)
        #expect(top.y + content.maxY == visible.maxY)   // 头顶贴着菜单栏下沿
        #expect(top.y + size.height > visible.maxY)     // 透明那截伸到菜单栏后面
        let left = PetBehavior.clamp(origin: CGPoint(x: -500, y: 300), size: size, content: content, into: visible)
        #expect(left.x + content.minX == visible.minX)
        let right = PetBehavior.clamp(origin: CGPoint(x: 5000, y: 300), size: size, content: content, into: visible)
        #expect(right.x + content.maxX == visible.maxX)
        let bottom = PetBehavior.clamp(origin: CGPoint(x: 600, y: -500), size: size, content: content, into: visible)
        #expect(bottom.y == visible.minY)
    }

    @Test func secondScreenWithNegativeOrigin() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1050)
        #expect(PetBehavior.clamp(origin: CGPoint(x: -2000, y: -10), size: size, into: left) == CGPoint(x: -1920, y: 0))
    }
}
