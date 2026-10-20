import Foundation
import Testing
@testable import JisiKit

struct PeerCodecTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func roundTrip(_ m: PeerMessage) -> PeerMessage? {
        guard let framed = PeerCodec.frame(m) else { return nil }
        guard let n = PeerCodec.bodyLength(framed.prefix(4)) else { return nil }
        #expect(n == framed.count - 4)
        return PeerCodec.decode(framed.dropFirst(4))
    }

    @Test func messagesRoundTrip() {
        var diary = Diary()
        diary.record(.pet, at: now)
        let session = WorkSession(startedAt: now, expectedClockOut: now.addingTimeInterval(9 * 3600))
        let snap = PeerSnapshot(session: session, schedule: .default, lastInteraction: Interaction(kind: .feed, date: now),
                                recentEvents: [CatEvent(kind: .clockIn, date: now)], diary: diary, lastFedAt: now,
                                meetingUntil: now.addingTimeInterval(1800), updatedAt: now, replyTo: UUID())
        let actions: [PeerCommand.Action] = [.clockIn, .clockOut, .pet, .feed, .ateMeal, .tookBreak, .play(.yarn),
                                             .mood(.tired), .startMeeting(minutes: 60), .endMeeting, .sync]
        var messages: [PeerMessage] = [.hello(version: PeerSync.version, name: "鸡丝的 iPhone"), .snapshot(snap)]
        messages += actions.map { .command(PeerCommand(action: $0, sentAt: now)) }
        for m in messages { #expect(roundTrip(m) == m) }
    }

    @Test func rejectsHugeLength() {
        #expect(PeerCodec.bodyLength(Data([0xFF, 0xFF, 0xFF, 0xFF])) == nil)
        #expect(PeerCodec.bodyLength(Data([0, 0, 1])) == nil)
        #expect(PeerCodec.bodyLength(Data([0, 0, 1, 0])) == 256)
    }

    @Test func garbageDoesNotDecode() {
        #expect(PeerCodec.decode(Data("not json".utf8)) == nil)
    }
}

struct PeerMergeTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func open(startedAt: Date) -> WorkSession {
        WorkSession(startedAt: startedAt, expectedClockOut: startedAt.addingTimeInterval(9 * 3600))
    }

    func ended(startedAt: Date, endedAt: Date) -> WorkSession {
        WorkSession(startedAt: startedAt, expectedClockOut: startedAt.addingTimeInterval(9 * 3600), endedAt: endedAt, userEnded: true)
    }

    @Test func clockInAppliesWhenNewerThanLastClockOut() {
        let c = PeerCommand(action: .clockIn, sentAt: now.addingTimeInterval(-600))
        #expect(PeerMerge.shouldApply(c, session: nil, now: now))
        #expect(PeerMerge.shouldApply(c, session: ended(startedAt: now.addingTimeInterval(-9000), endedAt: now.addingTimeInterval(-3600)), now: now))
        // iPhone 上在 Mac 点之后才下班的：Mac 那个「上班」已经过时
        #expect(!PeerMerge.shouldApply(c, session: ended(startedAt: now.addingTimeInterval(-9000), endedAt: now.addingTimeInterval(-60)), now: now))
        // 已经在上班
        #expect(!PeerMerge.shouldApply(c, session: open(startedAt: now.addingTimeInterval(-3600)), now: now))
    }

    @Test func clockOutAppliesOnlyToOlderOpenSession() {
        let c = PeerCommand(action: .clockOut, sentAt: now.addingTimeInterval(-60))
        #expect(PeerMerge.shouldApply(c, session: open(startedAt: now.addingTimeInterval(-3600)), now: now))
        // iPhone 上在 Mac 点下班之后又重新上班了
        #expect(!PeerMerge.shouldApply(c, session: open(startedAt: now.addingTimeInterval(-30)), now: now))
        #expect(!PeerMerge.shouldApply(c, session: nil, now: now))
        #expect(!PeerMerge.shouldApply(c, session: ended(startedAt: now.addingTimeInterval(-3600), endedAt: now.addingTimeInterval(-120)), now: now))
    }

    @Test func staleCommandsDropped() {
        let old = now.addingTimeInterval(-PeerSync.workCommandMaxAge - 1)
        #expect(!PeerMerge.shouldApply(PeerCommand(action: .clockIn, sentAt: old), session: nil, now: now))
        #expect(PeerMerge.shouldApply(PeerCommand(action: .pet, sentAt: old), session: nil, now: now))
        #expect(!PeerMerge.shouldApply(PeerCommand(action: .pet, sentAt: now.addingTimeInterval(-PeerSync.interactionMaxAge - 1)), session: nil, now: now))
        // 会已经开完了
        #expect(!PeerMerge.shouldApply(PeerCommand(action: .startMeeting(minutes: 30), sentAt: now.addingTimeInterval(-31 * 60)), session: nil, now: now))
        #expect(PeerMerge.shouldApply(PeerCommand(action: .startMeeting(minutes: 30), sentAt: now.addingTimeInterval(-10 * 60)), session: nil, now: now))
    }

    @Test func adoptOnlyAfterAllPendingAnswered() {
        let a = UUID(), b = UUID()
        func snap(_ reply: UUID?) -> PeerSnapshot {
            PeerSnapshot(session: nil, schedule: .default, lastInteraction: nil, recentEvents: [], diary: Diary(),
                         lastFedAt: nil, meetingUntil: nil, updatedAt: now, replyTo: reply)
        }
        #expect(PeerMerge.shouldAdopt(snap(nil), pending: []))
        #expect(!PeerMerge.shouldAdopt(snap(nil), pending: [a]))
        #expect(!PeerMerge.shouldAdopt(snap(a), pending: [a, b]))
        #expect(PeerMerge.shouldAdopt(snap(b), pending: [b]))
    }
}

struct PeerLocalTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func store() -> SharedStore {
        let d = UserDefaults(suiteName: "peer-test-\(UUID())")!
        return SharedStore(defaults: d)
    }

    @Test func clockInAndOutLikeIPhone() {
        let s = store()
        PeerLocal.apply(PeerCommand(action: .clockIn, sentAt: now), to: s)
        let session = try! #require(s.session)
        #expect(session.isOpen)
        #expect(session.startedAt == now)
        #expect(session.expectedClockOut > now)
        // 再点一次不换会话
        PeerLocal.apply(PeerCommand(action: .clockIn, sentAt: now.addingTimeInterval(60)), to: s)
        #expect(s.session?.id == session.id)

        PeerLocal.apply(PeerCommand(action: .clockOut, sentAt: now.addingTimeInterval(3600)), to: s)
        #expect(s.session?.isOpen == false)
        #expect(s.session?.endedAt == now.addingTimeInterval(3600))
    }

    @Test func interactionsRecorded() {
        let s = store()
        let t = Date()
        PeerLocal.apply(PeerCommand(action: .pet, sentAt: t), to: s)
        #expect(s.lastInteraction == Interaction(kind: .pet, date: t))
        #expect(s.snapshot(at: t).pose == .petted)
        PeerLocal.apply(PeerCommand(action: .startMeeting(minutes: 30), sentAt: t), to: s)
        #expect(s.meetingUntil == t.addingTimeInterval(1800))
        PeerLocal.apply(PeerCommand(action: .endMeeting, sentAt: t), to: s)
        #expect(s.meetingUntil == nil)
    }

    @Test func adoptCopiesEverything() {
        let phone = store(), mac = store()
        let t = Date()
        PeerLocal.apply(PeerCommand(action: .clockIn, sentAt: t), to: phone)
        PeerLocal.apply(PeerCommand(action: .feed, sentAt: t), to: phone)
        var sched = Schedule.default
        sched.workEnd = DayTime(17, 0)
        phone.schedule = sched
        mac.adopt(phone.peerSnapshot(now: t))
        #expect(mac.session == phone.session)
        #expect(mac.schedule == sched)
        #expect(mac.lastFedAt == t)
        #expect(mac.diary == phone.diary)
        #expect(mac.snapshot(at: t) == phone.snapshot(at: t))
    }
}

struct PeerNoticeTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    @Test func clockInMentionsClockOutTime() throws {
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 18, minute: 30)))
        let t = try #require(PeerNotice.text(for: .clockIn, expectedClockOut: end, delay: 2, calendar: calendar))
        #expect(t.title == "电脑上带鸡丝上班啦")
        #expect(t.body.contains("18:30 下班"))
        #expect(!t.body.contains("前点的"))
    }

    @Test func lateDeliverySaysWhen() throws {
        let t = try #require(PeerNotice.text(for: .clockOut, expectedClockOut: nil, delay: 25 * 60, calendar: calendar))
        #expect(t.title == "电脑上和鸡丝一起下班啦")
        #expect(t.body.contains("25 分钟 前点的") || t.body.contains("25 分钟前点的"))
        let h = try #require(PeerNotice.text(for: .clockOut, expectedClockOut: nil, delay: 90 * 60, calendar: calendar))
        #expect(h.body.contains("1 小时 30 分钟"))
    }

    @Test func otherActionsAreQuiet() {
        #expect(PeerNotice.text(for: .pet, expectedClockOut: nil, delay: 0) == nil)
        #expect(PeerNotice.text(for: .startMeeting(minutes: 30), expectedClockOut: nil, delay: 0) == nil)
    }
}
