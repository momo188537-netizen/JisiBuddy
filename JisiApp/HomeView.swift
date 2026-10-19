import JisiKit
import SwiftUI

/// 首页：鸡丝的小窝。
struct HomeView: View {
    @Environment(HomeModel.self) private var model
    @State private var showSettings = false
    @State private var showMemories = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if model.offerResume { resumeBanner }
                    if let gift = model.diary.pendingGift {
                        giftBanner(gift)
                    } else if let memory = model.diary.unseenMemory {
                        memoryCard(memory)
                    }

                    nest

                    HStack(spacing: 16) {
                        actionButton("摸摸", systemImage: "hand.raised.fill", action: model.pet)
                        actionButton("喂小鱼干", systemImage: "fish.fill", action: model.feed)
                    }

                    workButton

                    TodayView(today: model.diary.today.day == Diary.dayKey(Date(), calendar: .current) ? model.diary.today : DayCounts())

                    if !model.appGroupOK {
                        Label("App Group 未签出：锁屏小组件暂时看不到互动，只会按作息自己演。", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .background(Color.orange.opacity(0.06).ignoresSafeArea())
            .navigationTitle("鸡丝的小窝")
            .toolbar {
                Button("纪念册", systemImage: "book.closed") { showMemories = true }
                Button("设置", systemImage: "gearshape") { showSettings = true }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showMemories) { MemoriesView() }
            .alert("哎呀", isPresented: .constant(model.errorMessage != nil)) {
                Button("好") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .task {
                // 15 分钟一个时间桶，前台时每 30 秒看看鸡丝换没换动作。
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    model.refresh()
                }
            }
        }
    }

    private var nest: some View {
        VStack(spacing: 12) {
            Text(model.snapshot.line)
                .font(.title3.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.background, in: .rect(cornerRadius: 16))
                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                .contentTransition(.opacity)
                .animation(.default, value: model.snapshot.line)

            NestScene(
                snapshot: model.snapshot,
                owned: model.diary.ownedItems,
                light: model.light,
                reactionID: model.reactionID,
                onPet: model.pet,
                onItem: model.play
            )
            .frame(height: 340)
            .animation(.spring(duration: 0.4), value: model.snapshot.pose)

            Text(model.snapshot.pose.displayName)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// 低频：只在有新纪念时出现一次，收起后不再出现。
    private func memoryCard(_ memory: Memory) -> some View {
        HStack(spacing: 12) {
            JisiArt.prop("PropSparkles").frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(memory.title).font(.subheadline.weight(.semibold))
                Text(memory.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("收起", action: model.markMemoriesSeen)
                .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.orange.opacity(0.08), in: .rect(cornerRadius: 14))
        .onTapGesture { showMemories = true }
    }

    private func giftBanner(_ item: NestItem) -> some View {
        HStack(spacing: 12) {
            JisiArt.prop("PropGift").frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("小窝里多了一个\(item.displayName)")
                    .font(.subheadline.weight(.semibold))
                if let story = model.diary.memories.first(where: { $0.id == "item.\(item.rawValue)" })?.detail {
                    Text(story).font(.caption).foregroundStyle(.secondary)
                }
                Text("点它，鸡丝就会去玩。").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("好", action: model.dismissGift)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 14))
    }

    private var resumeBanner: some View {
        HStack {
            Text("鸡丝先回小窝了")
            Spacer()
            Button("继续陪伴", action: model.startWork)
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
        }
        .padding()
        .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 14))
    }

    @ViewBuilder
    private var workButton: some View {
        if model.isWorking, let s = model.session {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("已陪伴")
                    Text(timerInterval: s.startedAt...Date.distantFuture, countsDown: false)
                        .monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Button(action: model.endWork) {
                    Label("一起下班", systemImage: "house.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.isBusy)
            }
        } else if model.isRestDay {
            // 休息日：鸡丝窝在家里，「上班」退到不显眼的地方，周末加班也能用
            VStack(spacing: 8) {
                Label("今天休息，鸡丝窝在家里", systemImage: "sofa.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: model.startWork) {
                    Text("要加班？带上鸡丝")
                }
                .buttonStyle(.borderless)
                .font(.footnote)
                .disabled(model.isBusy)
            }
            .frame(maxWidth: .infinity)
        } else {
            Button(action: model.startWork) {
                Label("带鸡丝上班", systemImage: "briefcase.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isBusy)
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}
