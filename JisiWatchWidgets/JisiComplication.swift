import JisiWatchKit
import SwiftUI
import WidgetKit

struct WatchEntry: TimelineEntry {
    var date: Date
    var state: WatchState
}

/// 数据来自手表 App 写进手表端 App Group 的最近一次状态；手表 App 收到新状态后 reloadAllTimelines。
/// 倒计时用 `Text(timerInterval:)` 自己走，时间线只在到下班点那一刻换个样式。
struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry {
        let now = Date()
        return WatchEntry(date: now, state: WatchState(isWorking: true, startedAt: now.addingTimeInterval(-3 * 3600),
                                                       expectedClockOut: now.addingTimeInterval(2 * 3600 + 25 * 60),
                                                       updatedAt: now))
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : WatchEntry(date: Date(), state: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let state = load()
        let entries = WatchCountdown.entryDates(for: state, now: Date()).map { WatchEntry(date: $0, state: state) }
        completion(Timeline(entries: entries, policy: .never))
    }

    func load() -> WatchState {
        WatchStateStore().load() ?? .initial
    }
}

struct JisiComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchSync.complicationKind, provider: WatchProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("鸡丝")
        .description("上班时显示距下班还有多久。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct ComplicationView: View {
    var entry: WatchEntry
    @Environment(\.widgetFamily) private var family

    var phase: WorkPhase { entry.state.phase(at: entry.date) }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .accessoryCorner: corner
        default: circular
        }
    }

    // MARK: 圆形：鸡丝头像，上班时外圈是今天的进度

    var circular: some View {
        ZStack {
            if case .working(let since, let until) = phase {
                ProgressView(timerInterval: since...until, countsDown: false) { EmptyView() }
                    .progressViewStyle(.circular)
                    .widgetAccentable()
            } else {
                AccessoryWidgetBackground()
            }
            ComplicationFace()
                .padding(phase.isWorking ? 7 : 3)
        }
    }

    // MARK: 矩形：头像 + 两行字

    var rectangular: some View {
        HStack(spacing: 6) {
            ComplicationFace()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 0) {
                switch phase {
                case .off:
                    Text("鸡丝").font(.headline).widgetAccentable()
                    Text("还没上班").foregroundStyle(.secondary)
                case .working(_, let until):
                    Text("距下班").font(.headline).widgetAccentable()
                    Text(timerInterval: entry.date...until, countsDown: true)
                        .monospacedDigit()
                    Text("\(WatchCountdown.clockText(until)) 下班").font(.caption2).foregroundStyle(.secondary)
                case .overtime(_, let due):
                    Text("该下班啦").font(.headline).widgetAccentable()
                    Text("\(WatchCountdown.clockText(due)) 已到点").foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }

    // MARK: 一行字

    @ViewBuilder
    var inline: some View {
        switch phase {
        case .off:
            Text("鸡丝 · 还没上班")
        case .working(_, let until):
            Text("下班 \(Text(timerInterval: entry.date...until, countsDown: true))")
        case .overtime:
            Text("鸡丝 · 该下班啦")
        }
    }

    // MARK: 角落：中间头像，弧上倒计时

    var corner: some View {
        ComplicationFace()
            .padding(2)
            .widgetLabel {
                switch phase {
                case .off:
                    Text("还没上班")
                case .working(_, let until):
                    Text(timerInterval: entry.date...until, countsDown: true)
                case .overtime:
                    Text("该下班啦")
                }
            }
    }
}

/// 表盘上的头像：彩色表盘显示原图；染色表盘里 watchOS 11 起去色后染成强调色，watchOS 10 整张作为强调色。
struct ComplicationFace: View {
    var body: some View {
        if let image = WatchArt.smallFace {
            if #available(watchOS 11.0, *) {
                image.resizable()
                    .widgetAccentedRenderingMode(.accentedDesaturated)
                    .scaledToFit()
            } else {
                image.resizable().scaledToFit().widgetAccentable()
            }
        } else {
            Image(systemName: "cat.fill").resizable().scaledToFit().widgetAccentable()
        }
    }
}
