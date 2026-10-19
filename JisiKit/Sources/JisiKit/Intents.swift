import AppIntents
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// 让 App / Widget 扩展的 App Intents 元数据能找到本包里的 Intent（Xcode 16+）。
public struct JisiKitIntents: AppIntentsPackage {}

#if os(iOS)
public typealias JisiInteractiveIntent = LiveActivityIntent
#else
public typealias JisiInteractiveIntent = AppIntent
#endif

enum InteractionHandler {
    @MainActor
    static func handle(_ kind: InteractionKind, now: Date = Date()) async {
        SharedStore.shared.record(Interaction(kind: kind, date: now))
        JisiLog.append(kind.rawValue, at: now)
        await afterChange(now: now)
    }

    @MainActor
    static func handle(_ event: CatEventKind, now: Date = Date()) async {
        SharedStore.shared.record(CatEvent(kind: event, date: now))
        JisiLog.append(event.rawValue, at: now)
        await afterChange(now: now)
    }

    @MainActor
    static func afterChange(now: Date) async {
        #if os(iOS)
        await LiveActivityController.shared.refresh(now: now)
        #endif
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

public struct PetJisiIntent: JisiInteractiveIntent {
    public static let title: LocalizedStringResource = "摸摸鸡丝"
    public static let description = IntentDescription("摸一摸鸡丝的头。")
    public static let openAppWhenRun = false
    /// 锁屏卡片上不用解锁就能点（只改鸡丝自己的状态，不涉及隐私）。
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        await InteractionHandler.handle(.pet)
        return .result()
    }
}

public struct FeedJisiIntent: JisiInteractiveIntent {
    public static let title: LocalizedStringResource = "给鸡丝喂小鱼干"
    public static let description = IntentDescription("喂鸡丝一根小鱼干。")
    public static let openAppWhenRun = false
    /// 锁屏卡片上不用解锁就能点（只改鸡丝自己的状态，不涉及隐私）。
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        await InteractionHandler.handle(.feed)
        return .result()
    }
}

/// 饭点提醒里的「吃了」。
public struct AteMealIntent: AppIntent {
    public static let title: LocalizedStringResource = "我吃饭了"
    public static let openAppWhenRun = false
    /// 锁屏卡片上不用解锁就能点（只改鸡丝自己的状态，不涉及隐私）。
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        await InteractionHandler.handle(.ateMeal)
        return .result()
    }
}

/// Live Activity 上的「一起下班」。
public struct ClockOutIntent: JisiInteractiveIntent {
    public static let title: LocalizedStringResource = "和鸡丝一起下班"
    public static let openAppWhenRun = false
    /// 锁屏卡片上不用解锁就能点（只改鸡丝自己的状态，不涉及隐私）。
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        #if os(iOS)
        await LiveActivityController.shared.endWork()
        #else
        await InteractionHandler.handle(.clockOut)
        #endif
        return .result()
    }
}

/// 公开给 App 用（例如通知按钮回调）。
@MainActor
public enum JisiActions {
    public static func pet() async { await InteractionHandler.handle(.pet) }
    public static func feed() async { await InteractionHandler.handle(.feed) }
    public static func ateMeal() async { await InteractionHandler.handle(.ateMeal) }
    public static func tookBreak() async { await InteractionHandler.handle(.tookBreak) }
    /// 在小窝里点了毛线球 / 纸箱 / 软垫
    public static func play(_ item: NestItem) async { await InteractionHandler.handle(item.interaction) }
}

#if os(iOS)
import ActivityKit

/// 「带鸡丝上班」：Siri、快捷指令、控制中心都用它。是 LiveActivityIntent，所以 App 不在前台也能直接开始实时活动
/// （iOS 17 起 LiveActivityStartingIntent 已废弃，SDK 注明改用 LiveActivityIntent）。
public struct StartWorkIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "带鸡丝上班"
    public static let description = IntentDescription("开始带鸡丝上班，锁屏和灵动岛会出现鸡丝。")
    public static let openAppWhenRun = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return .result(dialog: "实时活动被关掉了，可以在 设置 > 鸡丝 里打开。")
        }
        try await LiveActivityController.shared.startWork()
        return .result(dialog: "鸡丝出发啦，一起上班！")
    }
}

/// 快捷指令 / Siri 用的「一起下班」（带一句回应）。
public struct ClockOutShortcutIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "和鸡丝一起下班"
    public static let description = IntentDescription("结束今天的陪伴，鸡丝回小窝。")
    public static let openAppWhenRun = false

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        await LiveActivityController.shared.endWork()
        return .result(dialog: "下班啦，回小窝咯。")
    }
}

/// 控制中心的开关：开 = 带鸡丝上班，关 = 一起下班。
@available(iOS 18.0, *)
public struct SetWorkingIntent: SetValueIntent, LiveActivityIntent {
    public static let title: LocalizedStringResource = "鸡丝上班"
    public static let openAppWhenRun = false

    @Parameter(title: "上班中")
    public var value: Bool

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        if value {
            if ActivityAuthorizationInfo().areActivitiesEnabled {
                try await LiveActivityController.shared.startWork()
            }
        } else {
            await LiveActivityController.shared.endWork()
        }
        return .result()
    }
}

/// 专注模式过滤器：在「工作」专注模式里加上「鸡丝」并打开「自动带鸡丝上班」，专注开启时就自动上班。
/// 同时是 LiveActivityIntent，后台也能开始实时活动。专注结束时系统会用默认值（关）再调用一次，不做任何事。
public struct JisiFocusFilter: SetFocusFilterIntent, LiveActivityIntent {
    public static let title: LocalizedStringResource = "鸡丝"
    public static let description: IntentDescription? = IntentDescription("开启这个专注模式时，自动带鸡丝上班。")

    @Parameter(title: "自动带鸡丝上班", default: false)
    public var autoClockIn: Bool

    public init() {}

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: autoClockIn ? "自动带鸡丝上班" : "不自动上班")
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        guard autoClockIn, ActivityAuthorizationInfo().areActivitiesEnabled else { return .result() }
        if SharedStore.shared.session?.isOpen != true {
            try await LiveActivityController.shared.startWork()
        }
        return .result()
    }
}
#endif

#if os(iOS)
/// 开会模式：期间鸡丝安静睡觉、提醒暂停，到时自动恢复（提醒本来就是按时间单次排的，开会那段直接跳过）。
@MainActor
public enum MeetingMode {
    public static let choices = [30, 60, 90]

    public static func start(minutes: Int, now: Date = Date()) async {
        SharedStore.shared.meetingUntil = now.addingTimeInterval(Double(minutes) * 60)
        JisiLog.append("meeting", at: now)
        await afterChange()
    }

    public static func end() async {
        SharedStore.shared.meetingUntil = nil
        await afterChange()
    }

    static func afterChange() async {
        await Reminders.shared.reschedule()
        if let session = SharedStore.shared.session, session.isOpen {
            await ClockOutNotice.schedule(for: session)
        }
        await InteractionHandler.afterChange(now: Date())
    }
}

/// 锁屏卡片 / 快捷指令：我在开会
public struct StartMeetingIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "我在开会"
    public static let description = IntentDescription("鸡丝安静睡觉，提醒暂停，到时自动恢复。")
    public static let openAppWhenRun = false
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "分钟", default: 60)
    public var minutes: Int

    public init() {}
    public init(minutes: Int) { self.minutes = minutes }

    @MainActor
    public func perform() async throws -> some IntentResult {
        await MeetingMode.start(minutes: max(5, minutes))
        return .result()
    }
}

/// 提前散会
public struct EndMeetingIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "开完会了"
    public static let openAppWhenRun = false
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        await MeetingMode.end()
        return .result()
    }
}
#endif
