import Foundation

// 只有 Command Line Tools 时没有 SwiftData 宏插件，scripts/test-kit.sh 会定义 JISI_NO_SWIFTDATA 跳过日志。
#if !JISI_NO_SWIFTDATA
import SwiftData

/// 互动与事件日志。只用于回看，不参与任何打分。
@Model
public final class LogEntry {
    public var date: Date
    /// "pet" / "feed" / "clockIn" / "clockOut" / "ateMeal" / "tookBreak"
    public var kind: String

    public init(date: Date, kind: String) {
        self.date = date
        self.kind = kind
    }
}

public enum JisiLog {
    /// 放在 App Group 容器里，App 和扩展（App Intents 可能在扩展进程里跑）都能写。
    public static let container: ModelContainer? = {
        let schema = Schema([LogEntry.self])
        let group = ModelConfiguration(schema: schema, groupContainer: .identifier(JisiConfig.appGroupID))
        if let c = try? ModelContainer(for: schema, configurations: group) { return c }
        // App Group 不可用时退回 App 自己的沙盒。
        return try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
    }()

    @MainActor
    public static func append(_ kind: String, at date: Date = Date()) {
        guard let context = container?.mainContext else { return }
        context.insert(LogEntry(date: date, kind: kind))
        try? context.save()
    }
}
#else
public enum JisiLog {
    @MainActor
    public static func append(_ kind: String, at date: Date = Date()) {}
}
#endif
