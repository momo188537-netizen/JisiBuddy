import Foundation
import Testing
@testable import JisiKit
@testable import JisiWatchKit

struct WatchCodecTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func stateRoundTrips() throws {
        let s = WatchState(isWorking: true, startedAt: now, expectedClockOut: now.addingTimeInterval(9 * 3600),
                           workEndMinutes: 18 * 60, updatedAt: now)
        let payload = WatchCodec.payload(for: s)
        #expect(WatchCodec.state(from: payload) == s)
        // 只放属性列表类型，WCSession 才收
        #expect(PropertyListSerialization.propertyList(payload, isValidFor: .binary))
    }

    @Test func commandRoundTrips() throws {
        for action in [WatchCommand.Action.clockIn, .clockOut, .sync, .stood] {
            let c = WatchCommand(action: action, sentAt: now)
            let payload = WatchCodec.payload(for: c)
            #expect(WatchCodec.command(from: payload) == c)
            #expect(PropertyListSerialization.propertyList(payload, isValidFor: .binary))
        }
    }

    @Test func stateAndCommandDontMixUp() {
        let state = WatchCodec.payload(for: .initial)
        let command = WatchCodec.payload(for: WatchCommand(action: .clockIn, sentAt: now))
        #expect(WatchCodec.command(from: state) == nil)
        #expect(WatchCodec.state(from: command) == nil)
    }

    @Test func garbageIsIgnored() {
        #expect(WatchCodec.state(from: [:]) == nil)
        #expect(WatchCodec.state(from: ["state": Data("nope".utf8)]) == nil)
        #expect(WatchCodec.command(from: ["command": "clockIn"]) == nil)
    }

    @Test func storeRoundTrips() throws {
        let defaults = try #require(UserDefaults(suiteName: "WatchCodecTests-\(UUID())"))
        let store = WatchStateStore(defaults: defaults)
        #expect(store.load() == nil)
        let s = WatchState(isWorking: false, workEndMinutes: 17 * 60, updatedAt: now)
        store.save(s)
        #expect(store.load() == s)
    }

    @Test func staleCommandsAreDropped() {
        let c = WatchCommand(action: .clockIn, sentAt: now)
        #expect(c.isFresh(now: now.addingTimeInterval(60)))
        #expect(!c.isFresh(now: now.addingTimeInterval(WatchSync.commandMaxAge + 1)))
    }
}

struct WatchStateTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    func date(_ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: h, minute: m))!
    }

    @Test func phases() {
        let s = WatchState(isWorking: true, startedAt: date(9), expectedClockOut: date(18, 30), updatedAt: date(9))
        #expect(s.phase(at: date(12)) == .working(since: date(9), until: date(18, 30)))
        #expect(s.phase(at: date(19)) == .overtime(since: date(9), due: date(18, 30)))
        #expect(WatchState.initial.phase(at: date(12)) == .off)
    }

    @Test func optimisticClockInUsesTodaysWorkEnd() {
        let s = WatchState.initial.applying(.clockIn, at: date(9, 5), calendar: calendar)
        #expect(s.isWorking)
        #expect(s.startedAt == date(9, 5))
        #expect(s.expectedClockOut == date(18, 30))
        #expect(s.updatedAt == date(9, 5))
    }

    @Test func optimisticClockInAfterWorkEndIsEightHours() {
        let s = WatchState.initial.applying(.clockIn, at: date(20), calendar: calendar)
        #expect(s.expectedClockOut == date(20).addingTimeInterval(8 * 3600))
    }

    @Test func clockInWhileWorkingKeepsSession() {
        let working = WatchState(isWorking: true, startedAt: date(9), expectedClockOut: date(18, 30), updatedAt: date(9))
        let s = working.applying(.clockIn, at: date(10), calendar: calendar)
        #expect(s.startedAt == date(9))
    }

    @Test func syncChangesNothing() {
        let working = WatchState(isWorking: true, startedAt: date(9), expectedClockOut: date(18, 30), updatedAt: date(9))
        #expect(working.applying(.sync, at: date(10), calendar: calendar) == working)
    }

    @Test func optimisticClockOut() {
        let working = WatchState(isWorking: true, startedAt: date(9), expectedClockOut: date(18, 30), updatedAt: date(9))
        let s = working.applying(.clockOut, at: date(18, 31), calendar: calendar)
        #expect(s.phase(at: date(18, 31)) == .off)
        #expect(s.startedAt == nil && s.expectedClockOut == nil)
    }

    @Test func olderStateDoesNotOverwriteNewer() {
        let newer = WatchState(isWorking: true, startedAt: date(9), expectedClockOut: date(18), updatedAt: date(9, 1))
        let older = WatchState(isWorking: false, updatedAt: date(9))
        #expect(!older.shouldReplace(newer))
        #expect(newer.shouldReplace(older))
    }

    @Test func fromPhoneSession() {
        let schedule = Schedule(workEnd: DayTime(17, 45))
        let open = WorkSession(startedAt: date(9), expectedClockOut: date(17, 45))
        let s = WatchState(session: open, schedule: schedule, now: date(10))
        #expect(s.isWorking && s.startedAt == date(9) && s.expectedClockOut == date(17, 45))
        #expect(s.workEndMinutes == 17 * 60 + 45)

        let ended = WorkSession(startedAt: date(9), expectedClockOut: date(17, 45), userEnded: true)
        let off = WatchState(session: ended, schedule: schedule, now: date(18))
        #expect(!off.isWorking && off.startedAt == nil)
        #expect(!WatchState(session: nil, schedule: schedule, now: date(18)).isWorking)
    }
}

struct WatchCountdownTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func entriesSwitchAtClockOut() {
        let end = start.addingTimeInterval(8 * 3600)
        let s = WatchState(isWorking: true, startedAt: start, expectedClockOut: end, updatedAt: start)
        #expect(WatchCountdown.entryDates(for: s, now: start) == [start, end])
        #expect(WatchCountdown.entryDates(for: s, now: end.addingTimeInterval(1)) == [end.addingTimeInterval(1)])
        #expect(WatchCountdown.entryDates(for: .initial, now: start) == [start])
    }

    @Test func progressIsClamped() {
        let end = start.addingTimeInterval(100)
        #expect(WatchCountdown.progress(since: start, until: end, now: start.addingTimeInterval(-5)) == 0)
        #expect(WatchCountdown.progress(since: start, until: end, now: start.addingTimeInterval(25)) == 0.25)
        #expect(WatchCountdown.progress(since: start, until: end, now: end.addingTimeInterval(5)) == 1)
        #expect(WatchCountdown.progress(since: start, until: start, now: start) == 1)
    }

    @Test func text() {
        #expect(WatchCountdown.text(-10) == "不到1分钟")
        #expect(WatchCountdown.text(59) == "不到1分钟")
        #expect(WatchCountdown.text(35 * 60) == "35分钟")
        #expect(WatchCountdown.text(2 * 3600) == "2小时")
        #expect(WatchCountdown.text(2 * 3600 + 5 * 60 + 30) == "2小时05分")
    }

    @Test func clockText() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let d = c.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 8, minute: 5))!
        #expect(WatchCountdown.clockText(d, calendar: c) == "8:05")
    }

    @Test func expressionsCycle() {
        var e = WatchExpression.calm
        var seen: Set<WatchExpression> = []
        for _ in WatchExpression.allCases { seen.insert(e); e = e.next }
        #expect(seen.count == WatchExpression.allCases.count)
        #expect(e == .calm)
    }

    @Test func watchArtIsBundled() {
        #expect(WatchArt.face != nil)
        #expect(WatchArt.smallFace != nil)
        #expect(WatchArt.fish != nil)
        #expect(WatchArt.closedFace != nil)
        #expect(WatchArt.closedSmallFace != nil)
    }
}

struct StandPlanTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    func date(_ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: h, minute: m))!
    }

    func working(interval: Int? = 50, meetingUntil: Date? = nil, lunch: Int? = 12 * 60) -> WatchState {
        WatchState(isWorking: true, startedAt: date(9), expectedClockOut: date(18), updatedAt: date(9),
                   standInterval: interval, meetingUntil: meetingUntil, lunchMinutes: lunch)
    }

    @Test func everyIntervalFromClockInUntilClockOut() {
        let dates = StandPlan.dates(state: working(lunch: nil), lastStood: nil, now: date(9), calendar: calendar)
        #expect(dates.first == date(9, 50))
        #expect(dates.dropFirst().first == date(10, 40))
        #expect(dates.allSatisfy { $0 < date(18) })
        #expect(zip(dates, dates.dropFirst()).allSatisfy { $1.timeIntervalSince($0) == 50 * 60 })
    }

    @Test func restartsFromLastStood() {
        let dates = StandPlan.dates(state: working(lunch: nil), lastStood: date(10, 5), now: date(10, 6), calendar: calendar)
        #expect(dates.first == date(10, 55))
    }

    @Test func offWhenDisabledOrNotWorkingOrAfterClockOut() {
        #expect(StandPlan.dates(state: working(interval: nil), lastStood: nil, now: date(9), calendar: calendar).isEmpty)
        #expect(StandPlan.dates(state: .initial, lastStood: nil, now: date(9), calendar: calendar).isEmpty)
        #expect(StandPlan.dates(state: working(), lastStood: nil, now: date(18, 1), calendar: calendar).isEmpty)
    }

    @Test func skipsLunchAndMeeting() {
        let lunch = StandPlan.dates(state: working(interval: 45), lastStood: nil, now: date(9), calendar: calendar)
        #expect(!lunch.contains { $0 >= date(11, 30) && $0 <= date(12, 30) })
        let meeting = StandPlan.dates(state: working(meetingUntil: date(11), lunch: nil), lastStood: nil, now: date(9, 10), calendar: calendar)
        #expect(!meeting.contains { $0 < date(11) })
        #expect(meeting.first == date(11, 30))
    }

    @Test func boundedAndOnlyFuture() {
        let s = WatchState(isWorking: true, startedAt: date(0), expectedClockOut: date(23, 59), updatedAt: date(0), standInterval: 45)
        let dates = StandPlan.dates(state: s, lastStood: nil, now: date(5), calendar: calendar)
        #expect(dates.count <= StandPlan.maxPending)
        #expect(dates.allSatisfy { $0 > date(5) })
    }

    @Test func oldIntervalsMigrateToChoices() {
        #expect(StandPlan.normalized(90) == 90)
        #expect(StandPlan.normalized(30) == 45)
        #expect(StandPlan.normalized(75) == 60 || StandPlan.normalized(75) == 90)
        #expect(StandPlan.normalized(180) == 90)
        #expect(StandPlan.choices.contains(StandPlan.defaultInterval))
    }

    @Test func phoneStateCarriesStandSettings() {
        let on = WatchState(session: nil, schedule: .default, now: date(9),
                            reminders: ReminderSettings(breaksEnabled: true, breakInterval: 60), meetingUntil: date(10))
        #expect(on.standInterval == 60 && on.meetingUntil == date(10) && on.lunchMinutes == 12 * 60)
        let off = WatchState(session: nil, schedule: .default, now: date(11),
                             reminders: ReminderSettings(breaksEnabled: false), meetingUntil: date(10))
        #expect(off.standInterval == nil && off.meetingUntil == nil)
    }

    /// 老版本手表 / iPhone 发的状态没有久坐字段，照样能解
    @Test func decodesStateWithoutStandFields() throws {
        let json = #"{"isWorking":true,"startedAt":1800000000,"expectedClockOut":1800030000,"workEndMinutes":1110,"updatedAt":1800000000}"#
        let payload: [String: Any] = ["state": Data(json.utf8)]
        let s = try #require(WatchCodec.state(from: payload))
        #expect(s.isWorking && s.standInterval == nil)
    }

    @Test func standTestPayload() {
        #expect(WatchCodec.isStandTest(WatchCodec.standTestPayload))
        #expect(!WatchCodec.isStandTest(WatchCodec.payload(for: .initial)))
    }

    /// iPhone 不再自己发休息提醒（避免和手表重复）
    @Test func phoneSendsNoBreakReminders() {
        let settings = ReminderSettings(mealsEnabled: true, breaksEnabled: true, breakInterval: 45)
        let items = ReminderPlan.upcoming(settings: settings, schedule: .default, now: date(8), calendar: calendar)
        #expect(!items.isEmpty)
        #expect(items.allSatisfy { $0.category == ReminderPlan.mealCategory })
        let onlyBreaks = ReminderSettings(mealsEnabled: false, breaksEnabled: true)
        #expect(ReminderPlan.upcoming(settings: onlyBreaks, schedule: .default, now: date(8), calendar: calendar).isEmpty)
    }
}
