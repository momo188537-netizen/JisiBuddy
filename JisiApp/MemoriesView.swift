import JisiKit
import SwiftUI

/// 纪念册：只列真实发生过的事（时间 + 次数），不打分、不评价。
struct MemoriesView: View {
    @Environment(HomeModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let d = model.diary
        NavigationStack {
            List {
                Section {
                    LabeledContent("认识鸡丝", value: d.firstDay.map { "\(Self.daysSince($0)) 天" } ?? "今天")
                    LabeledContent("一起度过的日子", value: "\(d.activeDays.count) 天")
                    LabeledContent("一起下班", value: "\(d.clockOutCount) 次")
                    LabeledContent("一起吃饭", value: "\(d.mealCount) 次")
                } footer: {
                    Text("只记发生过的事，忘了打开也没关系。")
                }

                if !d.moods.isEmpty {
                    Section("下班心情") {
                        moodRow("这周", Self.counts(d, .weekOfYear))
                        moodRow("这个月", Self.counts(d, .month))
                    }
                }

                Section("小窝里的东西") {
                    if d.items.isEmpty {
                        Text("还没有。一起上班、下班、吃饭时，鸡丝会慢慢找到。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(NestItem.allCases.filter { d.items[$0] != nil }) { item in
                        HStack(spacing: 12) {
                            itemIcon(item).frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                Text("\(d.items[item]!, format: .dateTime.month().day()) 得到")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("回忆") {
                    ForEach(d.memories.sorted { $0.date > $1.date }) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.title).font(.body.weight(.medium))
                            Text(m.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("纪念册")
            .toolbar { Button("完成") { dismiss() } }
        }
    }

    private func moodRow(_ title: String, _ counts: [ClockOutMood: Int]) -> some View {
        LabeledContent(title) {
            Text(ClockOutMood.allCases.map { "\($0.emoji) \($0.label) \(counts[$0, default: 0]) 次" }.joined(separator: "  "))
                .font(.footnote)
        }
    }

    static func counts(_ d: Diary, _ unit: Calendar.Component, now: Date = Date(), calendar: Calendar = .current) -> [ClockOutMood: Int] {
        guard let interval = calendar.dateInterval(of: unit, for: now) else { return [:] }
        return d.moodCounts(from: interval.start, to: interval.end)
    }

    @ViewBuilder
    private func itemIcon(_ item: NestItem) -> some View {
        switch item {
        case .yarn: JisiArt.prop("ItemYarn")
        case .box: JisiArt.prop("ItemBox")
        case .cushion: CushionView().padding(.vertical, 10)
        }
    }

    static func daysSince(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        (calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0) + 1
    }
}

/// 首页下方可折叠的「今天的小事」。
struct TodayView: View {
    var today: DayCounts
    @AppStorage("todayExpanded") private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                if today.isEmpty {
                    Text("今天还很安静。").foregroundStyle(.secondary)
                }
                if let t = today.firstClockIn { row("\(t.formatted(date: .omitted, time: .shortened)) 一起出门上班") }
                if today.meals > 0 { row("一起吃了 \(today.meals) 顿饭") }
                if today.breaks > 0 { row("起来休息了 \(today.breaks) 次") }
                if today.pets > 0 { row("摸了鸡丝 \(today.pets) 次") }
                if today.feeds > 0 { row("喂了 \(today.feeds) 根小鱼干") }
                if let t = today.clockOut { row("\(t.formatted(date: .omitted, time: .shortened)) 一起下班") }
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            Text("今天的小事").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
        }
        .tint(.primary)
        .padding()
        .background(Color.orange.opacity(0.06), in: .rect(cornerRadius: 14))
    }

    private func row(_ text: String) -> some View {
        Label {
            Text(text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: "pawprint.fill").foregroundStyle(.orange)
        }
    }
}
