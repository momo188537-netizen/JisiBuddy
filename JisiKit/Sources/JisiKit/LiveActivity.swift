import Foundation

/// 回前台时是否显示「鸡丝先回小窝了，继续陪伴」。纯函数，绝不自动重启。
public enum ResumePolicy {
    public static func shouldOfferResume(session: WorkSession?, activityAlive: Bool, now: Date) -> Bool {
        guard let s = session, s.isOpen, !s.userEnded, !activityAlive else { return false }
        return now >= s.startedAt && now < s.expectedClockOut
    }
}

/// 点「带鸡丝上班 / 继续陪伴」时怎么处理已有的 Live Activity：同一时间最多一个。纯函数，方便测试。
public enum ActivityPlan {
    public struct Existing: Hashable, Sendable {
        public var id: String
        public var sessionID: UUID
        /// active 或 stale（还在锁屏上）
        public var alive: Bool

        public init(id: String, sessionID: UUID, alive: Bool) {
            self.id = id
            self.sessionID = sessionID
            self.alive = alive
        }
    }

    public struct Decision: Hashable, Sendable {
        /// 沿用这个活动，不再 request 新的
        public var reuse: String?
        /// 立即结束这些活动
        public var end: [String]
    }

    /// `sessionID`：这次要陪伴的会话。属于它且还活着的活动留一个，其余全部结束。
    public static func onStart(sessionID: UUID, existing: [Existing]) -> Decision {
        let keep = existing.first { $0.sessionID == sessionID && $0.alive }?.id
        return Decision(reuse: keep, end: existing.map(\.id).filter { $0 != keep })
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
        /// 「一起下班」的时间；有值时卡片显示下班样式、计时停住、不再显示按钮。
        public var endedAt: Date?

        public init(pose: CatPose, line: String, lastFedAt: Date?, endedAt: Date? = nil) {
            self.pose = pose
            self.line = line
            self.lastFedAt = lastFedAt
            self.endedAt = endedAt
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
            $0.attributes.sessionID == id && Self.isAlive($0)
        }
    }

    static func isAlive(_ activity: Activity<JisiActivityAttributes>) -> Bool {
        activity.activityState == .active || activity.activityState == .stale
    }

    /// 正在陪伴（会话没结束）。活动可能被划掉了，这时首页显示「继续陪伴」横幅，但仍可「一起下班」。
    public var isWorking: Bool { store.session.map { $0.isOpen } ?? false }

    public var isRunning: Bool { current != nil }

    public var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// 「带鸡丝上班」。如果已有进行中的会话就沿用它（恢复）。同一时间最多一个 Live Activity。
    @discardableResult
    public func startWork(now: Date = Date(), calendar: Calendar = .current) async throws -> WorkSession {
        var session: WorkSession
        if let s = store.session, s.isOpen, now < s.expectedClockOut {
            session = s
            session.userDismissed = false
        } else {
            var clockOut = store.schedule.clockOut(on: now, calendar: calendar)
            if clockOut <= now { clockOut = now.addingTimeInterval(8 * 3600) }
            session = WorkSession(startedAt: now, expectedClockOut: clockOut)
            store.record(CatEvent(kind: .clockIn, date: now))
            JisiLog.append(CatEventKind.clockIn.rawValue, at: now)
        }

        let activities = Activity<JisiActivityAttributes>.activities
        let plan = ActivityPlan.onStart(sessionID: session.id, existing: activities.map {
            .init(id: $0.id, sessionID: $0.attributes.sessionID, alive: Self.isAlive($0))
        })
        for activity in activities where plan.end.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let activity: Activity<JisiActivityAttributes>
        if let id = plan.reuse, let existing = activities.first(where: { $0.id == id }) {
            activity = existing
            await activity.update(content(now: now, session: session))
        } else {
            let attributes = JisiActivityAttributes(
                sessionID: session.id,
                startedAt: session.startedAt,
                expectedClockOut: session.expectedClockOut
            )
            activity = try Activity.request(
                attributes: attributes,
                content: content(now: now, session: session),
                pushType: nil
            )
        }
        session.activityID = activity.id
        store.session = session
        observe(activity)
        WidgetCenter.shared.reloadAllTimelines()
        return session
    }

    /// 「一起下班」：先把所有鸡丝活动更新成下班样式（计时停住、没有按钮），一分钟后从锁屏消失。
    public func endWork(now: Date = Date()) async {
        if var s = store.session, s.isOpen {
            s.userEnded = true
            s.endedAt = now
            store.session = s
            store.record(CatEvent(kind: .clockOut, date: now))
            JisiLog.append(CatEventKind.clockOut.rawValue, at: now)
        }
        let final = ActivityContent(state: endedState(now: now), staleDate: nil)
        for activity in Activity<JisiActivityAttributes>.activities {
            await activity.end(final, dismissalPolicy: .after(now.addingTimeInterval(60)))
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 互动或事件之后把最新快照推给 Live Activity。
    public func refresh(now: Date = Date()) async {
        guard let session = store.session else { return }
        let content = content(now: now, session: session)
        for activity in Activity<JisiActivityAttributes>.activities
        where activity.attributes.sessionID == session.id && Self.isAlive(activity) {
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

    func endedState(now: Date) -> JisiActivityAttributes.ContentState {
        .init(pose: .lounging, line: "下班啦，回小窝", lastFedAt: store.lastFedAt, endedAt: now)
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
