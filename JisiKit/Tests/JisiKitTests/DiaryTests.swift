import Foundation
import Testing
@testable import JisiKit

struct DiaryTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    func date(_ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func firstClockInGivesYarnAndFirstClockOutGivesCushion() {
        var d = Diary()
        d.record(.clockIn, at: date(20, 9), calendar: calendar)
        #expect(d.ownedItems == [.yarn])
        #expect(d.pendingGift == .yarn)
        let new = d.record(.clockOut, at: date(20, 18, 30), calendar: calendar)
        #expect(d.ownedItems == [.yarn, .cushion])
        #expect(new.map(\.id).contains("firstClockOut"))
        #expect(new.map(\.id).contains("item.cushion"))
        #expect(d.firstClockOut == date(20, 18, 30))
    }

    @Test func mealOrBreakGivesBox() {
        var d = Diary()
        d.record(.tookBreak, at: date(20), calendar: calendar)
        #expect(d.ownedItems == [.box])
    }

    @Test func surpriseAfterThreeDays() {
        var d = Diary()
        d.record(.pet, at: date(20), calendar: calendar)
        d.record(.pet, at: date(21), calendar: calendar)
        #expect(d.ownedItems.isEmpty)
        d.record(.pet, at: date(22), calendar: calendar)
        #expect(d.ownedItems == [.box])
        // 每次最多一件
        d.record(.pet, at: date(22, 11), calendar: calendar)
        #expect(d.ownedItems.count == 2)
    }

    @Test func playingDoesNotGiveDirectGifts() {
        var d = Diary()
        d.record(.played, at: date(20), calendar: calendar)
        d.record(.feed, at: date(20), calendar: calendar)
        #expect(d.ownedItems.isEmpty)
    }

    @Test func mealMilestonesCountRealMeals() {
        var d = Diary()
        for i in 0..<10 { d.record(.ateMeal, at: date(20).addingTimeInterval(Double(i) * 3600), calendar: calendar) }
        #expect(d.mealCount == 10)
        let ids = d.memories.map(\.id)
        #expect(ids.contains("meal.1"))
        #expect(ids.contains("meal.10"))
        #expect(!ids.contains("meal.5"))
    }

    @Test func anniversariesUseFirstDay() {
        var d = Diary()
        d.record(.pet, at: date(1), calendar: calendar)
        d.checkAnniversaries(now: date(7), calendar: calendar)
        #expect(!d.memories.map(\.id).contains("days.7"))
        d.checkAnniversaries(now: date(8), calendar: calendar)
        #expect(d.memories.map(\.id).contains("days.7"))
        d.checkAnniversaries(now: date(31), calendar: calendar)
        #expect(d.memories.map(\.id).contains("days.30"))
        #expect(!d.memories.map(\.id).contains("days.100"))
    }

    @Test func memoriesAreAddedOnce() {
        var d = Diary()
        d.record(.clockOut, at: date(20), calendar: calendar)
        d.record(.clockOut, at: date(21), calendar: calendar)
        #expect(d.memories.filter { $0.id == "firstClockOut" }.count == 1)
    }

    @Test func showsOnlyNewestUnseenMemory() {
        var d = Diary()
        d.record(.clockIn, at: date(20, 9), calendar: calendar)
        d.record(.clockOut, at: date(20, 18), calendar: calendar)
        #expect(d.unseenMemory != nil)
        d.markMemoriesSeen()
        #expect(d.unseenMemory == nil)
    }

    @Test func todayCountsResetOnNewDay() {
        var d = Diary()
        d.record(.pet, at: date(20), calendar: calendar)
        d.record(.feed, at: date(20), calendar: calendar)
        d.record(.clockIn, at: date(20, 9), calendar: calendar)
        #expect(d.today.pets == 1 && d.today.feeds == 1 && d.today.firstClockIn != nil)
        d.record(.pet, at: date(21), calendar: calendar)
        #expect(d.today.pets == 1 && d.today.feeds == 0 && d.today.firstClockIn == nil)
    }

    @Test func replayFromLog() {
        let log: [(kind: String, date: Date)] = [
            ("clockIn", date(20, 9)), ("pet", date(20, 10)), ("yarn", date(20, 11)),
            ("ateMeal", date(20, 12)), ("clockOut", date(20, 18)), ("unknown", date(20, 19)),
        ]
        let d = Diary.replaying(log, now: date(20, 20), calendar: calendar)
        #expect(d.ownedItems == [.yarn, .box, .cushion])
        #expect(d.pendingGift == nil)
        #expect(d.mealCount == 1 && d.clockOutCount == 1 && d.petCount == 1)
        // 只留一条没看过的
        #expect(d.memories.filter { !d.seenMemoryIDs.contains($0.id) }.count == 1)
    }

    @Test func storeFeedsDiaryAndToys() {
        let store = SharedStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        #expect(store.toys == Toy.deskProps)
        store.record(CatEvent(kind: .clockIn, date: Date()))
        #expect(store.toys.contains(.yarn))
        #expect(store.brainInput().items == [.yarn])
        store.record(CatEvent(kind: .clockOut, date: Date()))
        #expect(store.brainInput().items.contains(.cushion))
    }

    @Test func diaryRoundTrips() throws {
        var d = Diary()
        d.record(.clockIn, at: date(20), calendar: calendar)
        let data = try JSONEncoder().encode(d)
        #expect(try JSONDecoder().decode(Diary.self, from: data) == d)
    }
}
