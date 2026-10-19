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

struct ActivityPlanTests {
    let current = UUID()
    let old = UUID()

    @Test func requestsNewWhenNothingRunning() {
        let d = ActivityPlan.onStart(sessionID: current, existing: [])
        #expect(d.reuse == nil)
        #expect(d.end.isEmpty)
    }

    @Test func reusesLiveActivityOfSameSession() {
        let d = ActivityPlan.onStart(sessionID: current, existing: [
            .init(id: "a", sessionID: current, alive: true),
        ])
        #expect(d.reuse == "a")
        #expect(d.end.isEmpty)
    }

    /// 截图里的 bug：上一次下班的卡片还挂在锁屏上，又开了一张新的。
    @Test func endsLeftoversFromOtherSessions() {
        let d = ActivityPlan.onStart(sessionID: current, existing: [
            .init(id: "old", sessionID: old, alive: false),
            .init(id: "old2", sessionID: old, alive: true),
        ])
        #expect(d.reuse == nil)
        #expect(Set(d.end) == ["old", "old2"])
    }

    @Test func keepsOnlyOneOfDuplicates() {
        let d = ActivityPlan.onStart(sessionID: current, existing: [
            .init(id: "a", sessionID: current, alive: true),
            .init(id: "b", sessionID: current, alive: true),
            .init(id: "dead", sessionID: current, alive: false),
        ])
        #expect(d.reuse == "a")
        #expect(Set(d.end) == ["b", "dead"])
    }
}

#if os(iOS)
struct ActivityStateTests {
    @Test func decodesOldStateWithoutEndedAt() throws {
        let json = #"{"pose":"lounging","line":"喵","lastFedAt":null}"#
        let s = try JSONDecoder().decode(JisiActivityAttributes.ContentState.self, from: Data(json.utf8))
        #expect(s.endedAt == nil)
    }
}
#endif

struct ClockOutTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// 下班后会话关闭：不再显示恢复横幅，首页回到「带鸡丝上班」。
    @Test func endedSessionIsClosedAndNotResumable() {
        var s = WorkSession(startedAt: start, expectedClockOut: start.addingTimeInterval(9 * 3600))
        #expect(s.isOpen)
        s.userEnded = true
        s.endedAt = start.addingTimeInterval(3600)
        #expect(!s.isOpen)
        #expect(!ResumePolicy.shouldOfferResume(session: s, activityAlive: false, now: start.addingTimeInterval(7200)))
    }
}

struct ArtTests {
    /// 锁屏 Widget 只能放小图，原图 512px 会让 Widget 渲染失败。
    @Test func smallFaceIsSmall() throws {
        let url = try #require(JisiArt.faceURL)
        let cg = try #require(JisiArt.thumbnail(url: url, maxPixel: JisiArt.smallFacePixels))
        #expect(max(cg.width, cg.height) <= JisiArt.smallFacePixels)
    }
}

extension ArtTests {
    @Test func monoFaceIsBundled() {
        #expect(JisiArt.monoFace != nil)
    }
}

struct ClockOutNoticeTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()
    func date(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }

    @Test func firesAtClockOutOnWorkday() {
        let s = WorkSession(startedAt: date(20, 9), expectedClockOut: date(20, 18, 30))
        #expect(ClockOutNotice.fireDate(session: s, schedule: .default, deliveredDay: nil, now: date(20, 9), calendar: calendar) == date(20, 18, 30))
    }

    @Test func notAfterClockingOutOrPastTime() {
        var s = WorkSession(startedAt: date(20, 9), expectedClockOut: date(20, 18, 30))
        #expect(ClockOutNotice.fireDate(session: s, schedule: .default, deliveredDay: nil, now: date(20, 19), calendar: calendar) == nil)
        s.userEnded = true
        #expect(ClockOutNotice.fireDate(session: s, schedule: .default, deliveredDay: nil, now: date(20, 9), calendar: calendar) == nil)
    }

    @Test func notOnRestDays() {
        // 2026-10-24 周六
        let s = WorkSession(startedAt: date(24, 10), expectedClockOut: date(24, 18))
        #expect(ClockOutNotice.fireDate(session: s, schedule: .default, deliveredDay: nil, now: date(24, 10), calendar: calendar) == nil)
    }

    @Test func atMostOncePerDay() {
        let s = WorkSession(startedAt: date(20, 19), expectedClockOut: date(20, 23))
        #expect(ClockOutNotice.fireDate(session: s, schedule: .default, deliveredDay: 20261020, now: date(20, 19), calendar: calendar) == nil)
        #expect(ClockOutNotice.fireDate(session: s, schedule: .default, deliveredDay: 20261019, now: date(20, 19), calendar: calendar) != nil)
    }

    @Test func deliveredOnlyIfTimePassed() {
        #expect(ClockOutNotice.deliveredDay(scheduledAt: date(20, 18), previous: nil, now: date(20, 19), calendar: calendar) == 20261020)
        // 提前下班取消了，没发出去，不算
        #expect(ClockOutNotice.deliveredDay(scheduledAt: date(20, 18), previous: nil, now: date(20, 17), calendar: calendar) == nil)
    }
}
