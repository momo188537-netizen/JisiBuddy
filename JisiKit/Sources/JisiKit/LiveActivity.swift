import Foundation

/// 回前台时是否显示「鸡丝先回小窝了，继续陪伴」。纯函数，绝不自动重启。
public enum ResumePolicy {
    public static func shouldOfferResume(session: WorkSession?, activityAlive: Bool, now: Date) -> Bool {
        guard let s = session, s.isOpen, !s.userEnded, !activityAlive else { return false }
        return now >= s.startedAt && now < s.expectedClockOut
    }
}

#if os(iOS)
import ActivityKit
import WidgetKit

public struct JisiActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var pose: CatPose
        public var line: String
        public var lastFedAt: Date?

        public init(pose: CatPose, line: String, lastFedAt: Date?) {
            self.pose = pose
            self.line = line
            self.lastFedAt = lastFedAt
        }
    }

    public var sessionID: UUID
    public var startedAt: Date
    public var expectedClockOut: Date

    public init(sessionID: UUID, startedAt: Date, expectedClockOut: Date) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.expectedClockOut = expectedClockOut
    }
}

/// 管理「带鸡丝上班」的 Live Activity。
@MainActor
public final class LiveActivityController {
    public static let shared = LiveActivityController()

    private let store = SharedStore.shared
    private var observers: [String: Task<Void, Never>] = [:]

    public var current: Activity<JisiActivityAttributes>? {
        let id = store.session?.id
        return Activity<JisiActivityAttributes>.activities.first {
            $0.attributes.sessionID == id && ($0.activityState == .active || $0.activityState == .stale)
        }
    }

    public var isRunning: Bool { current != nil }

    public var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// 「带鸡丝上班」。如果已有进行中的会话就沿用它（恢复）。
    @discardableResult
    public func startWork(now: Date = Date(), calendar: Calendar = .current) throws -> WorkSession {
        var session: WorkSession
        if let s = store.session, ResumePolicy.shouldOfferResume(session: s, activityAlive: isRunning, now: now) {
            session = s
            session.userDismissed = false
        } else {
            var clockOut = store.schedule.clockOut(on: now, calendar: calendar)
            if clockOut <= now { clockOut = now.addingTimeInterval(8 * 3600) }
            session = WorkSession(startedAt: now, expectedClockOut: clockOut)
            store.record(CatEvent(kind: .clockIn, date: now))
            JisiLog.append(CatEventKind.clockIn.rawValue, at: now)
        }

        let attributes = JisiActivityAttributes(
            sessionID: session.id,
            startedAt: session.startedAt,
            expectedClockOut: session.expectedClockOut
        )
        let activity = try Activity.request(
            attributes: attributes,
            content: content(now: now, session: session),
            pushType: nil
        )
        session.activityID = activity.id
        store.session = session
        observe(activity)
        WidgetCenter.shared.reloadAllTimelines()
        return session
    }

    /// 「一起下班」。
    public func endWork(now: Date = Date()) async {
        if var s = store.session, s.isOpen {
            s.userEnded = true
            s.endedAt = now
            store.session = s
            store.record(CatEvent(kind: .clockOut, date: now))
            JisiLog.append(CatEventKind.clockOut.rawValue, at: now)
        }
        let final = ActivityContent(state: state(now: now), staleDate: nil)
        for activity in Activity<JisiActivityAttributes>.activities {
            await activity.end(final, dismissalPolicy: .after(now.addingTimeInterval(10 * 60)))
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 互动或事件之后把最新快照推给 Live Activity。
    public func refresh(now: Date = Date()) async {
        guard let session = store.session else { return }
        let content = content(now: now, session: session)
        for activity in Activity<JisiActivityAttributes>.activities
        where activity.attributes.sessionID == session.id {
            await activity.update(content)
        }
    }

    /// App 启动时调用：重新挂上对现有活动的监听。
    public func reattach() {
        for activity in Activity<JisiActivityAttributes>.activities { observe(activity) }
    }

    public func shouldOfferResume(now: Date = Date()) -> Bool {
        ResumePolicy.shouldOfferResume(session: store.session, activityAlive: isRunning, now: now)
    }

    // MARK: -

    func state(now: Date) -> JisiActivityAttributes.ContentState {
        let s = store.snapshot(at: now)
        return .init(pose: s.pose, line: s.line, lastFedAt: store.lastFedAt)
    }

    func content(now: Date, session: WorkSession) -> ActivityContent<JisiActivityAttributes.ContentState> {
        // 到下班点后显示「该下班啦」样式。
        ActivityContent(state: state(now: now), staleDate: session.expectedClockOut)
    }

    private func observe(_ activity: Activity<JisiActivityAttributes>) {
        guard observers[activity.id] == nil else { return }
        let store = self.store
        observers[activity.id] = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                if state == .dismissed, var s = store.session, s.id == activity.attributes.sessionID, !s.userEnded {
                    s.userDismissed = true
                    store.session = s
                }
                if state == .dismissed || state == .ended {
                    self?.observers[activity.id] = nil
                    break
                }
            }
        }
    }
}
#endif
