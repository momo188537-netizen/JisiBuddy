import JisiKit
import SwiftUI

/// 首页：鸡丝的小窝。
struct HomeView: View {
    @Environment(HomeModel.self) private var model
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if model.offerResume { resumeBanner }

                    nest

                    HStack(spacing: 16) {
                        actionButton("摸摸", systemImage: "hand.raised.fill", action: model.pet)
                        actionButton("喂小鱼干", systemImage: "fish.fill", action: model.feed)
                    }

                    workButton

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
                Button("设置", systemImage: "gearshape") { showSettings = true }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
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

            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(Color.orange.opacity(0.18))
                    .frame(height: 60)
                    .offset(y: 10)
                JisiCatView(
                    pose: model.snapshot.pose,
                    toy: model.snapshot.toy,
                    animated: true,
                    reactionID: model.reactionID
                )
                .frame(width: 240, height: 240)
                .onTapGesture(perform: model.pet)
            }
            .padding(.top, 8)

            Text(model.snapshot.pose.displayName)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var resumeBanner: some View {
        HStack {
            Text("鸡丝先回小窝了")
            Spacer()
            Button("继续陪伴", action: model.startWork)
                .buttonStyle(.borderedProminent)
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
            }
        } else {
            Button(action: model.startWork) {
                Label("带鸡丝上班", systemImage: "briefcase.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
