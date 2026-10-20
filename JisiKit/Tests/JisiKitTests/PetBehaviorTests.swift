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
