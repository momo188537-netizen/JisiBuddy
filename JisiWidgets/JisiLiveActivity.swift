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
                    Text(context.isStale ? "到点啦，一起下班吧" : context.state.line)
                        .font(.callout)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityButtons(isStale: context.isStale)
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

/// 陪伴时长：从上班开始正着数，系统自己走秒，不需要更新活动。
func companionTimer(_ context: ActivityViewContext<JisiActivityAttributes>) -> Text {
    Text(timerInterval: context.attributes.startedAt...Date.distantFuture, countsDown: false)
}

struct LockScreenActivityView: View {
    let context: ActivityViewContext<JisiActivityAttributes>

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                JisiCatView(pose: context.state.pose, animated: false)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.isStale ? "到点啦，一起下班吧" : context.state.line)
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
            ActivityButtons(isStale: context.isStale)
        }
        .padding()
    }
}

struct ActivityButtons: View {
    var isStale: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: PetJisiIntent()) {
                Label("摸摸", systemImage: "hand.raised.fill").frame(maxWidth: .infinity)
            }
            Button(intent: FeedJisiIntent()) {
                Label("喂食", systemImage: "fish.fill").frame(maxWidth: .infinity)
            }
            Button(intent: ClockOutIntent()) {
                Label("一起下班", systemImage: "house.fill").frame(maxWidth: .infinity)
            }
            .tint(isStale ? .orange : .gray)
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .tint(.orange)
    }
}
