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
        #if os(macOS)
        // Mac 不签 App Group，日志放 App 自己的 Application Support（只记 Mac 上点的，回看以 iPhone 为准）
        return try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
        #else
        let group = ModelConfiguration(schema: schema, groupContainer: .identifier(JisiConfig.appGroupID))
        if let c = try? ModelContainer(for: schema, configurations: group) { return c }
        // App Group 不可用时退回 App 自己的沙盒。
        return try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
        #endif
    }()

    @MainActor
    public static func append(_ kind: String, at date: Date = Date()) {
        guard let context = container?.mainContext else { return }
        context.insert(LogEntry(date: date, kind: kind))
        try? context.save()
    }

    /// 全部日志（导出备份用）
    @MainActor
    public static func allRecords() -> [JisiBackup.LogRecord] {
        let entries = (try? container?.mainContext.fetch(FetchDescriptor<LogEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        return entries.map { .init(date: $0.date, kind: $0.kind) }
    }

    /// 用备份里的日志替换现有日志
    @MainActor
    public static func replaceAll(with records: [JisiBackup.LogRecord]) {
        guard let context = container?.mainContext else { return }
        try? context.delete(model: LogEntry.self)
        for r in records { context.insert(LogEntry(date: r.date, kind: r.kind)) }
        try? context.save()
    }

    /// 老版本升级上来时还没有 Diary：用完整日志补算一次（物件、纪念、次数）。
    @MainActor
    public static func backfillDiaryIfNeeded(store: SharedStore = .shared) {
        guard store.storedDiary == nil else { return }
        let entries = (try? container?.mainContext.fetch(FetchDescriptor<LogEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        store.diary = Diary.replaying(entries.map { ($0.kind, $0.date) })
    }
}
#else
public enum JisiLog {
    @MainActor
    public static func append(_ kind: String, at date: Date = Date()) {}

    @MainActor
    public static func backfillDiaryIfNeeded(store: SharedStore = .shared) {
        if store.storedDiary == nil { store.diary = Diary() }
    }

    @MainActor
    public static func allRecords() -> [JisiBackup.LogRecord] { [] }

    @MainActor
    public static func replaceAll(with records: [JisiBackup.LogRecord]) {}
}
#endif
