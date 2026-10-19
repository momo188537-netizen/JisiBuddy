import ActivityKit
import AppIntents
import JisiKit
import SwiftUI
import WidgetKit

/// 「带鸡丝上班」的锁屏 Live Activity + 灵动岛。
struct JisiLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JisiActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .activityBackgroundTint(Color.orange.opacity(0.15))
                .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    face(context).frame(width: 56, height: 56)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("已陪伴").font(.caption2).foregroundStyle(.secondary)
                        companionTimer(context).font(.callout.monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(headline(context))
                        .font(.callout)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.endedAt == nil {
                        ActivityButtons(isStale: context.isStale)
                    }
                }
            } compactLeading: {
                face(context).frame(width: 24, height: 24)
            } compactTrailing: {
                companionTimer(context)
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: 44)
            } minimal: {
                face(context).frame(width: 22, height: 22)
            }
            .keylineTint(.orange)
        }
    }

    func face(_ context: ActivityViewContext<JisiActivityAttributes>) -> some View {
        JisiCatView(pose: context.state.pose, animated: false)
    }
}

/// 陪伴时长：从上班开始正着数，系统自己走秒，不需要更新活动；下班后停在下班那一刻。
func companionTimer(_ context: ActivityViewContext<JisiActivityAttributes>) -> Text {
    if let end = context.state.endedAt {
        let start = context.attributes.startedAt
        return Text(timerInterval: start...max(start, end), pauseTime: end, countsDown: false)
    }
    return Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
}

func headline(_ context: ActivityViewContext<JisiActivityAttributes>) -> String {
    if context.state.endedAt != nil { return context.state.line }
    return context.isStale ? "到点啦，一起下班吧" : context.state.line
}

struct LockScreenActivityView: View {
    let context: ActivityViewContext<JisiActivityAttributes>

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                JisiCatView(pose: context.state.pose, animated: false)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline(context))
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text("已陪伴")
                        companionTimer(context).monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if let fed = context.state.lastFedAt {
                        Text("上次喂小鱼干 \(fed, style: .time)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if context.state.endedAt == nil {
                ActivityButtons(isStale: context.isStale)
            }
        }
        .padding()
    }
}

/// 锁屏上不用解锁就能点（LiveActivityIntent 在 App 进程里后台执行）。
struct ActivityButtons: View {
    var isStale: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: PetJisiIntent()) {
                Label("摸摸", systemImage: "hand.raised.fill")
            }
            .buttonStyle(SolidButtonStyle(fill: .orange))
            Button(intent: FeedJisiIntent()) {
                Label("喂食", systemImage: "fish.fill")
            }
            .buttonStyle(SolidButtonStyle(fill: .orange))
            Button(intent: ClockOutIntent()) {
                Label("一起下班", systemImage: "house.fill")
            }
            .buttonStyle(SolidButtonStyle(fill: Color(red: 0.45, green: 0.26, blue: 0.13)))
        }
        .font(.caption.weight(.semibold))
    }
}

/// 实心底 + 白字：系统自带的 .bordered 在锁屏半透明背景上太淡，像被禁用。
struct SolidButtonStyle: ButtonStyle {
    var fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(fill.opacity(configuration.isPressed ? 0.7 : 1), in: .capsule)
    }
}
