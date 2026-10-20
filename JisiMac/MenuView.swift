import JisiKit
import SwiftUI

/// 点菜单栏头像弹出的小窗：鸡丝、此刻在干嘛、上下班、摸摸喂食、开会。
struct MenuView: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            if let until = model.meetingUntil { meetingBanner(until) }
            if model.askMood { moodCard }

            Text(model.snapshot.line)
                .font(.callout.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.background, in: .rect(cornerRadius: 12))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                .contentTransition(.opacity)
                .animation(.default, value: model.snapshot.line)

            JisiCatView(pose: model.snapshot.pose, toy: model.snapshot.toy, reactionID: model.reactionID)
                .frame(height: 150)
                .contentShape(.rect)
                .onTapGesture(perform: model.pet)
                .animation(.spring(duration: 0.4), value: model.snapshot.pose)
                .help("摸摸鸡丝")

            Text(model.snapshot.pose.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            workStatus

            HStack(spacing: 8) {
                button("摸摸", systemImage: "hand.raised.fill", action: model.pet)
                button("喂小鱼干", systemImage: "fish.fill", action: model.feed)
            }

            let owned = NestItem.allCases.filter { model.diary.ownedItems.contains($0) }
            if !owned.isEmpty {
                HStack(spacing: 8) {
                    ForEach(owned) { item in
                        Button(item.displayName) { model.play(item) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }

            workButton

            if model.meetingUntil == nil, model.isWorking {
                Menu {
                    ForEach([30, 60, 90], id: \.self) { m in
                        Button("\(m) 分钟") { model.startMeeting(minutes: m) }
                    }
                } label: {
                    Label("我在开会", systemImage: "bell.slash")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(.callout)
            }

            Divider()
            today
            footer
        }
        .padding(16)
        .frame(width: 300)
        .background(Color.orange.opacity(0.05))
        .onAppear { model.refresh() }
    }

    // MARK: -

    @ViewBuilder
    private var workStatus: some View {
        if let s = model.session, s.isOpen {
            VStack(spacing: 2) {
                if model.now < s.expectedClockOut {
                    HStack(spacing: 4) {
                        Text("距下班")
                        Text(timerInterval: Date.now...s.expectedClockOut, countsDown: true).monospacedDigit()
                    }
                    .font(.headline)
                } else {
                    Text("该下班啦").font(.headline)
                }
                HStack(spacing: 4) {
                    Text("已陪伴")
                    Text(timerInterval: s.startedAt...Date.distantFuture, countsDown: false).monospacedDigit()
                    Text("· \(s.expectedClockOut.formatted(date: .omitted, time: .shortened)) 下班")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } else {
            Text(model.isRestDay ? "今天休息，鸡丝窝在家里" : "还没上班")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var workButton: some View {
        if model.isWorking {
            Button(action: model.clockOut) {
                Label("一起下班", systemImage: "house.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        } else {
            Button(action: model.clockIn) {
                Label(model.isRestDay ? "要加班？带上鸡丝" : "带鸡丝上班", systemImage: "briefcase.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var moodCard: some View {
        VStack(spacing: 8) {
            Text("今天累不累？").font(.subheadline.weight(.semibold))
            HStack(spacing: 6) {
                ForEach(ClockOutMood.allCases) { m in
                    Button {
                        model.answerMood(m)
                    } label: {
                        VStack(spacing: 0) {
                            Text(m.emoji).font(.title2)
                            Text(m.label).font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            Button("跳过") { model.answerMood(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1), in: .rect(cornerRadius: 10))
    }

    private func meetingBanner(_ until: Date) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.slash.fill").foregroundStyle(.indigo)
            HStack(spacing: 4) {
                Text("开会中，还剩")
                Text(timerInterval: Date.now...max(until, Date.now), countsDown: true).monospacedDigit()
            }
            .font(.callout.weight(.semibold))
            Spacer(minLength: 0)
            Button("提前结束", action: model.endMeeting)
                .controlSize(.small)
        }
        .padding(10)
        .background(Color.indigo.opacity(0.08), in: .rect(cornerRadius: 10))
    }

    private var today: some View {
        let t = model.diary.today.day == Diary.dayKey(model.now, calendar: .current) ? model.diary.today : DayCounts()
        var parts: [String] = []
        if t.pets > 0 { parts.append("摸了 \(t.pets) 次") }
        if t.feeds > 0 { parts.append("喂了 \(t.feeds) 根小鱼干") }
        if t.meals > 0 { parts.append("吃了 \(t.meals) 顿饭") }
        if t.breaks > 0 { parts.append("休息 \(t.breaks) 次") }
        return Text(parts.isEmpty ? "今天还很安静。" : "今天：" + parts.joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.isConnected ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(syncText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button("退出") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    private var syncText: String {
        if let name = model.peerName {
            return model.outbox.isEmpty ? "已和 \(name) 同步" : "正在同步到 \(name)…"
        }
        if model.listenerError != nil { return "局域网没打开：去 系统设置 > 隐私与安全性 > 本地网络 允许鸡丝" }
        let pending = model.outbox.isEmpty ? "" : "，\(model.outbox.count) 个操作待同步"
        return "iPhone 没连上（打开 iPhone 上的鸡丝就会同步\(pending)）"
    }

    private func button(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}
