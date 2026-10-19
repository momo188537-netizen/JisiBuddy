import Foundation
import Testing
@testable import JisiKit

struct ResumePolicyTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var clockOut: Date { start.addingTimeInterval(9 * 3600) }
    var mid: Date { start.addingTimeInterval(3600) }

    @Test func offersWhenActivityGoneDuringWork() {
        let s = WorkSession(startedAt: start, expectedClockOut: clockOut)
        #expect(ResumePolicy.shouldOfferResume(session: s, activityAlive: false, now: mid))
    }

    @Test func offersAfterUserSwipedAwayToo() {
        let s = WorkSession(startedAt: start, expectedClockOut: clockOut, userDismissed: true)
        #expect(ResumePolicy.shouldOfferResume(session: s, activityAlive: false, now: mid))
    }

    @Test func noOfferWhenStillAlive() {
        let s = WorkSession(startedAt: start, expectedClockOut: clockOut)
        #expect(!ResumePolicy.shouldOfferResume(session: s, activityAlive: true, now: mid))
    }

    @Test func noOfferWhenUserEnded() {
        let s = WorkSession(startedAt: start, expectedClockOut: clockOut, userEnded: true)
        #expect(!ResumePolicy.shouldOfferResume(session: s, activityAlive: false, now: mid))
    }

    @Test func noOfferAfterClockOutOrWithoutSession() {
        let s = WorkSession(startedAt: start, expectedClockOut: clockOut)
        #expect(!ResumePolicy.shouldOfferResume(session: s, activityAlive: false, now: clockOut))
        #expect(!ResumePolicy.shouldOfferResume(session: nil, activityAlive: false, now: mid))
    }
}

struct SharedStoreTests {
    func makeStore() -> SharedStore {
        let name = "test-\(UUID().uuidString)"
        return SharedStore(defaults: UserDefaults(suiteName: name)!)
    }

    @Test func roundTrips() {
        let store = makeStore()
        #expect(store.schedule == .default)
        var s = Schedule.default
        s.workEnd = DayTime(17, 0)
        store.schedule = s
        #expect(store.schedule.workEnd == DayTime(17, 0))

        let now = Date()
        store.record(Interaction(kind: .feed, date: now))
        #expect(store.lastInteraction?.kind == .feed)
        #expect(store.lastFedAt == now)
        #expect(store.snapshot(at: now).pose == .fed)
    }

    @Test func dropsOldEvents() {
        let store = makeStore()
        store.recentEvents = [
            CatEvent(kind: .clockIn, date: Date().addingTimeInterval(-25 * 3600)),
            CatEvent(kind: .ateMeal, date: Date()),
        ]
        #expect(store.recentEvents.map(\.kind) == [.ateMeal])
    }
}
