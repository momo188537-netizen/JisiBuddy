import Foundation
import Testing
@testable import JisiKit

struct BackupTests {
    func makeStore() -> SharedStore {
        SharedStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    }

    func filledStore() -> SharedStore {
        let store = makeStore()
        var s = Schedule.default
        s.workEnd = DayTime(17, 45)
        s.workdays = [2, 3, 4]
        store.schedule = s
        store.reminders = ReminderSettings(mealsEnabled: true, breaksEnabled: true, breakInterval: 60)
        let t = Date(timeIntervalSince1970: 1_800_000_000.123_456_7)
        store.record(CatEvent(kind: .clockIn, date: t))
        store.record(Interaction(kind: .feed, date: t.addingTimeInterval(60)))
        store.record(CatEvent(kind: .ateMeal, date: t.addingTimeInterval(3600)))
        store.record(CatEvent(kind: .clockOut, date: t.addingTimeInterval(7200)))
        return store
    }

    @Test func exportThenImportIsIdentical() throws {
        let source = filledStore()
        let log: [JisiBackup.LogRecord] = [.init(date: Date(timeIntervalSince1970: 1_800_000_000.5), kind: "clockIn"),
                                           .init(date: Date(timeIntervalSince1970: 1_800_000_060.25), kind: "feed")]
        let backup = source.makeBackup(log: log, now: Date(timeIntervalSince1970: 1_800_010_000))
        let data = try backup.encoded()

        let decoded = try JisiBackup.decode(data)
        #expect(decoded == backup)

        let target = makeStore()
        target.restore(decoded)
        #expect(target.makeBackup(log: decoded.log, now: backup.exportedAt) == backup)
        #expect(target.schedule.workEnd == DayTime(17, 45))
        #expect(target.diary.ownedItems == [.yarn, .box, .cushion])
        #expect(target.lastFedAt == source.lastFedAt)
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: JisiBackup.ImportError.notABackup) { try JisiBackup.decode(Data("{}".utf8)) }
        #expect(throws: JisiBackup.ImportError.notABackup) { try JisiBackup.decode(Data("hello".utf8)) }
        let wrong = #"{"format":"com.zixu.jisibuddy.backup","version":1}"#
        #expect(throws: JisiBackup.ImportError.notABackup) { try JisiBackup.decode(Data(wrong.utf8)) }
    }

    @Test func rejectsNewerVersion() {
        let newer = #"{"format":"com.zixu.jisibuddy.backup","version":99}"#
        #expect(throws: JisiBackup.ImportError.newerVersion(99)) { try JisiBackup.decode(Data(newer.utf8)) }
    }

    @Test func restoreKeepsCurrentSession() {
        let target = makeStore()
        let session = WorkSession(startedAt: Date(), expectedClockOut: Date().addingTimeInterval(3600))
        target.session = session
        target.restore(filledStore().makeBackup(log: []))
        #expect(target.session == session)
    }

    @Test func fileNameHasDate() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let d = c.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!
        #expect(JisiBackup.fileName(for: d, calendar: c) == "鸡丝备份-2026-10-20.json")
    }
}
