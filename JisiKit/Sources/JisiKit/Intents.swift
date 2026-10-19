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
