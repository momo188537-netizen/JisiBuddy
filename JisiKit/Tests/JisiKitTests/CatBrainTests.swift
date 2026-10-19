import Foundation
import Testing
@testable import JisiKit

struct CatBrainTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    /// 2026-10-20 是周二
    func date(_ hour: Int, _ minute: Int = 0, day: Int = 20, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    func input(_ now: Date, interaction: Interaction? = nil, events: [CatEvent] = []) -> CatBrain.Input {
        CatBrain.Input(now: now, lastInteraction: interaction, recentEvents: events, calendar: calendar)
    }

    @Test func isDeterministic() {
        let a = CatBrain.snapshot(input(date(10, 7)))
        let b = CatBrain.snapshot(input(date(10, 7)))
        #expect(a == b)
    }

    @Test func sameBucketSameBehavior() {
        let a = CatBrain.snapshot(input(date(10, 0, second: 1)))
        let b = CatBrain.snapshot(input(date(10, 14, second: 59)))
        #expect(a.pose == b.pose && a.line == b.line && a.toy == b.toy)
    }

    @Test func neverRepeatsPreviousBucket() {
        for day in [18, 19, 20, 21] {
            let start = calendar.startOfDay(for: date(0, day: day))
            var previous: CatSnapshot?
            for b in 0..<96 {
                let s = CatBrain.snapshot(input(start.addingTimeInterval(Double(b) * 900 + 60)))
                if let p = previous {
                    #expect(!(p.pose == s.pose && p.line == s.line && p.toy == s.toy), "day \(day) bucket \(b)")
                }
                previous = s
            }
        }
    }

    @Test func variesAcrossDays() {
        let lines = (10...20).map { CatBrain.snapshot(input(date(10, day: $0))).line }
        #expect(Set(lines).count > 1)
    }

    @Test func sleepsAtNight() {
        #expect(CatBrain.snapshot(input(date(3, 0))).pose == .sleeping)
        #expect(CatBrain.snapshot(input(date(23, 45))).pose == .sleeping)
    }

    @Test func neverSleepsDuringWork() {
        for minute in stride(from: 0, to: 9 * 60, by: 15) {
            let s = CatBrain.snapshot(input(date(9, 30).addingTimeInterval(Double(minute) * 60)))
            #expect(s.pose != .sleeping)
            #expect(s.pose != .petted && s.pose != .fed)
        }
    }

    @Test func workHoursAreLoungingOrPlaying() {
        let s = CatBrain.snapshot(input(date(10, 30)))
        #expect([.lounging, .playing].contains(s.pose))
        if s.pose == .playing { #expect(s.toy != nil) }
    }

    @Test func interactionBeatsEverything() {
        let now = date(3, 0)
        let pet = Interaction(kind: .pet, date: now.addingTimeInterval(-30))
        let event = CatEvent(kind: .clockIn, date: now.addingTimeInterval(-10))
        #expect(CatBrain.snapshot(input(now, interaction: pet, events: [event])).pose == .petted)

        let feed = Interaction(kind: .feed, date: now)
        #expect(CatBrain.snapshot(input(now, interaction: feed)).pose == .fed)
    }

    @Test func interactionExpires() {
        let now = date(10, 0)
        let old = Interaction(kind: .pet, date: now.addingTimeInterval(-CatBrain.reactionDuration))
        #expect(CatBrain.snapshot(input(now, interaction: old)).pose != .petted)
        let future = Interaction(kind: .pet, date: now.addingTimeInterval(60))
        #expect(CatBrain.snapshot(input(now, interaction: future)).pose != .petted)
    }

    @Test func eventBeatsAutonomous() {
        let now = date(23, 50)
        let out = CatEvent(kind: .clockOut, date: now.addingTimeInterval(-60))
        let s = CatBrain.snapshot(input(now, events: [out]))
        #expect(s.pose == .lounging)
        #expect(Lines.clockOut.contains(s.line))

        let stale = CatEvent(kind: .clockOut, date: now.addingTimeInterval(-CatBrain.eventDuration - 1))
        #expect(CatBrain.snapshot(input(now, events: [stale])).pose == .sleeping)
    }

    @Test func latestEventWins() {
        let now = date(10, 0)
        let events = [
            CatEvent(kind: .ateMeal, date: now.addingTimeInterval(-60)),
            CatEvent(kind: .clockIn, date: now.addingTimeInterval(-300)),
        ]
        #expect(Lines.ateMeal.contains(CatBrain.snapshot(input(now, events: events)).line))
    }

    /// 通知里点「吃了」：鸡丝也吃小鱼干；其他事件不吃。
    @Test func ateMealShowsFedPose() {
        let now = date(12, 5)
        let ate = CatBrain.snapshot(input(now, events: [CatEvent(kind: .ateMeal, date: now.addingTimeInterval(-30))]))
        #expect(ate.pose == .fed)
        let rested = CatBrain.snapshot(input(now, events: [CatEvent(kind: .tookBreak, date: now.addingTimeInterval(-30))]))
        #expect(rested.pose != .fed)
    }

    @Test func noToysStillWorks() {
        var i = input(date(10, 0))
        i.toys = []
        for b in 0..<36 {
            i.now = date(9, 30).addingTimeInterval(Double(b) * 900)
            let s = CatBrain.snapshot(i)
            #expect(s.toy == nil)
        }
    }

    @Test func timelineCoversADayOnBucketBoundaries() {
        let now = date(10, 7)
        let entries = CatBrain.timeline(input(now))
        #expect(entries.first?.date == now)
        #expect(entries.count == 97) // 起点 + 96 个桶边界
        #expect(entries[1].date == date(10, 15))
        #expect(zip(entries, entries.dropFirst()).allSatisfy { $0.date < $1.date })
    }

    @Test func timelineIncludesReactionExpiry() {
        let now = date(10, 7)
        let pet = Interaction(kind: .pet, date: now)
        let entries = CatBrain.timeline(input(now, interaction: pet))
        #expect(entries.first?.pose == .petted)
        let expiry = now.addingTimeInterval(CatBrain.reactionDuration)
        let atExpiry = entries.first { $0.date == expiry }
        #expect(atExpiry != nil && atExpiry?.pose != .petted)
    }

    @Test func dayTimeWrapsMidnight() {
        #expect(DayTime.isWithin(DayTime(1, 0), from: DayTime(23, 0), to: DayTime(7, 0)))
        #expect(!DayTime.isWithin(DayTime(12, 0), from: DayTime(23, 0), to: DayTime(7, 0)))
        #expect(DayTime(-1, 0) == DayTime(23, 0))
    }

    @Test func weekendIsNotWorkingHours() {
        // 2026-10-24 是周六
        #expect(!Schedule.default.isWorkingHours(date(10, day: 24), calendar: calendar))
        #expect(Schedule.default.isWorkingHours(date(10, day: 20), calendar: calendar))
    }
}
