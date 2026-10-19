import Foundation

/// 鸡丝的全部数据：设置、状态、物件、回忆、完整互动日志。导出成一个 JSON 文件，可以存进「文件」App。
/// 不包含进行中的「上班」会话（Live Activity 是这台手机上的，恢复了也对不上）。
public struct JisiBackup: Codable, Hashable, Sendable {
    public static let formatID = "com.zixu.jisibuddy.backup"
    public static let currentVersion = 1

    public var format = formatID
    public var version = currentVersion
    public var exportedAt: Date
    public var schedule: Schedule
    public var reminders: ReminderSettings
    public var preferences: Preferences?
    public var lastInteraction: Interaction?
    public var lastFedAt: Date?
    public var recentEvents: [CatEvent]
    public var diary: Diary
    public var log: [LogRecord]

    public struct LogRecord: Codable, Hashable, Sendable {
        public var date: Date
        public var kind: String
        public init(date: Date, kind: String) {
            self.date = date
            self.kind = kind
        }
    }

    public enum ImportError: LocalizedError, Equatable {
        case notABackup
        case newerVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .notABackup: "这不是鸡丝的备份文件。"
            case .newerVersion(let v): "这个备份来自更新的版本（v\(v)），请先更新 App。"
            }
        }
    }

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        // 时间存成数字（精确到微秒以下），导出再导入完全一致
        return e
    }()

    public static let decoder: JSONDecoder = {
        JSONDecoder()
    }()

    public func encoded() throws -> Data { try Self.encoder.encode(self) }

    /// 读取并校验格式和版本。
    public static func decode(_ data: Data) throws -> JisiBackup {
        struct Header: Decodable { var format: String?; var version: Int? }
        guard let header = try? decoder.decode(Header.self, from: data), header.format == formatID else {
            throw ImportError.notABackup
        }
        if let v = header.version, v > currentVersion { throw ImportError.newerVersion(v) }
        do {
            return try decoder.decode(JisiBackup.self, from: data)
        } catch {
            throw ImportError.notABackup
        }
    }

    /// 建议的文件名，例如「鸡丝备份-2026-10-20.json」
    public static func fileName(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "鸡丝备份-%04d-%02d-%02d.json", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

extension SharedStore {
    public func makeBackup(log: [JisiBackup.LogRecord], now: Date = Date()) -> JisiBackup {
        JisiBackup(
            exportedAt: now,
            schedule: schedule,
            reminders: reminders,
            preferences: preferences,
            lastInteraction: lastInteraction,
            lastFedAt: lastFedAt,
            recentEvents: recentEvents,
            diary: diary,
            log: log
        )
    }

    /// 覆盖当前数据（日志由调用方另外写回 SwiftData）。进行中的上班会话保留不动。
    public func restore(_ b: JisiBackup) {
        schedule = b.schedule
        reminders = b.reminders
        preferences = b.preferences ?? Preferences()
        lastInteraction = b.lastInteraction
        lastFedAt = b.lastFedAt
        set(b.recentEvents, for: .events)
        diary = b.diary
    }
}
