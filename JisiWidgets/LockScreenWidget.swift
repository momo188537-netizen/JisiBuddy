import JisiKit
import SwiftUI
import WidgetKit

struct CatEntry: TimelineEntry {
    var date: Date
    var snapshot: CatSnapshot
}

/// 用 CatBrain 预算未来 24 小时的条目（每 15 分钟一条），用完再要新的。
/// App 或 Intent 里发生互动后会 reloadAllTimelines。
struct CatProvider: TimelineProvider {
    func placeholder(in context: Context) -> CatEntry {
        CatEntry(date: Date(), snapshot: CatSnapshot(pose: .lounging, line: "陪你上班中～", date: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (CatEntry) -> Void) {
        let s = SharedStore.shared.snapshot()
        completion(CatEntry(date: s.date, snapshot: s))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CatEntry>) -> Void) {
        let snapshots = CatBrain.timeline(SharedStore.shared.brainInput())
        completion(Timeline(entries: snapshots.map { CatEntry(date: $0.date, snapshot: $0) }, policy: .atEnd))
    }
}

struct JisiLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: JisiConfig.widgetKind, provider: CatProvider()) { entry in
            LockScreenView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("鸡丝")
        .description("鸡丝在锁屏上陪你。")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}

struct LockScreenView: View {
    @Environment(\.widgetFamily) private var family
    var entry: CatEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                JisiCatView(pose: entry.snapshot.pose, toy: entry.snapshot.toy, animated: false)
                    .padding(4)
            }
            .widgetAccentable()
        default:
            HStack(spacing: 6) {
                JisiCatView(pose: entry.snapshot.pose, toy: entry.snapshot.toy, animated: false)
                    .frame(width: 44, height: 44)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 2) {
                    Text("鸡丝 · \(entry.snapshot.pose.displayName)")
                        .font(.caption2.weight(.semibold))
                        .widgetAccentable()
                    Text(entry.snapshot.line)
                        .font(.footnote)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

#Preview(as: .accessoryRectangular) {
    JisiLockScreenWidget()
} timeline: {
    CatEntry(date: .now, snapshot: CatSnapshot(pose: .playing, line: "偷偷摸个鱼", toy: .laptop, date: .now))
    CatEntry(date: .now, snapshot: CatSnapshot(pose: .sleeping, line: "呼噜呼噜……", date: .now))
}
