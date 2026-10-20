import JisiWatchKit
import SwiftUI

/// 唯一的页面：鸡丝头像（点一下换表情）+ 状态 + 大按钮。
struct WatchHomeView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let phase = model.state.phase(at: context.date)
            VStack(spacing: 6) {
                Button {
                    withAnimation(.spring(duration: 0.3)) { model.tapCat() }
                } label: {
                    WatchCatFace(expression: model.expression)
                        .frame(maxWidth: 84, maxHeight: 84)
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                .accessibilityHint("点一下鸡丝换个表情")

                StatusText(phase: phase)

                Spacer(minLength: 0)

                if phase.isWorking {
                    Button("一起下班") { model.send(.clockOut) }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                } else {
                    Button("上班") { model.send(.clockIn) }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }

                if phase.isWorking, let next = model.nextStand, next > context.date {
                    Text("久坐提醒 \(WatchCountdown.clockText(next))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let note = model.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .disabled(model.isSending)
            .padding(.horizontal, 4)
        }
    }
}

struct StatusText: View {
    var phase: WorkPhase

    var body: some View {
        switch phase {
        case .off:
            Text("还没上班")
                .font(.headline)
        case .working(let since, let until):
            VStack(spacing: 0) {
                HStack(spacing: 2) {
                    Text("距下班")
                    Text(timerInterval: min(Date.now, until)...until, countsDown: true)
                        .monospacedDigit()
                }
                .font(.headline)
                HStack(spacing: 2) {
                    Text("已上班")
                    Text(since, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        case .overtime(let since, _):
            VStack(spacing: 0) {
                Text("该下班啦")
                    .font(.headline)
                HStack(spacing: 2) {
                    Text("已上班")
                    Text(since, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    WatchHomeView().environment(WatchModel.shared)
}
