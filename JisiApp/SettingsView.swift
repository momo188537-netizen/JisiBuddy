import JisiKit
import JisiWatchKit
import SwiftUI

struct SettingsView: View {
    @Environment(HomeModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let weekdays = [(2, "一"), (3, "二"), (4, "三"), (5, "四"), (6, "五"), (7, "六"), (1, "日")]

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("作息") {
                    time("上班", $model.schedule.workStart)
                    time("下班", $model.schedule.workEnd)
                    time("午饭", $model.schedule.lunch)
                    time("晚饭", $model.schedule.dinner)
                    time("睡觉", $model.schedule.bedtime)
                    time("起床", $model.schedule.wake)
                }
                Section {
                    HStack {
                        ForEach(weekdays, id: \.0) { day, name in
                            let on = model.schedule.workdays.contains(day)
                            Button(name) {
                                if on { model.schedule.workdays.remove(day) } else { model.schedule.workdays.insert(day) }
                            }
                            .buttonStyle(.bordered)
                            .tint(on ? .orange : .gray)
                        }
                    }
                } header: {
                    Text("工作日")
                } footer: {
                    Text("休息日鸡丝窝在家里，不发下班提醒；饭点提醒照常。周末加班也可以带上鸡丝。")
                }

                Section {
                    Toggle("饭点提醒", isOn: $model.reminders.mealsEnabled)
                    Toggle("久坐提醒（Apple Watch）", isOn: $model.reminders.breaksEnabled)
                    if model.reminders.breaksEnabled {
                        Picker("坐多久提醒", selection: $model.reminders.breakInterval) {
                            ForEach(StandPlan.choices, id: \.self) { Text("\($0) 分钟").tag($0) }
                        }
                    }
                } header: {
                    Text("提醒")
                } footer: {
                    Text("饭点提醒里可以直接点「吃了」，鸡丝会知道。久坐提醒只在手表上轻敲手腕：带鸡丝上班期间，从上班或上次点「站起来了」开始计时，开会和午饭前后不打扰。想用它代替手表自带的站立提醒，可以在 iPhone「Watch」App > 活动 里关掉「站立提醒」。")
                }
                Section {
                    Toggle("下班时问一句「今天累不累」", isOn: Binding(
                        get: { model.preferences.askMoodAtClockOut },
                        set: { model.preferences.askMoodAtClockOut = $0 }
                    ))
                } footer: {
                    Text("在 App 里点「一起下班」后出现，可以跳过。纪念册里只记你选了什么，不做评价。")
                }

                BackupSection()

                #if DEBUG
                Section("调试") {
                    Button("1 分钟后发一条测试饭点提醒") {
                        Task { await Reminders.shared.sendTestMeal() }
                    }
                    Button("1 分钟后发一条测试下班提醒") {
                        Task { await Reminders.shared.sendTestClockOut() }
                    }
                    Button("手表：1 分钟后发一条久坐提醒") { PhoneWatchLink.shared.sendStandTest() }
                    Button("得到全部小窝物件") { model.debugUnlockAllItems() }
                }
                #endif
            }
            .navigationTitle("设置")
            .toolbar {
                Button("完成") { dismiss() }
            }
        }
    }

    private func time(_ title: String, _ value: Binding<DayTime>) -> some View {
        DatePicker(title, selection: Binding(
            get: { Calendar.current.date(bySettingHour: value.wrappedValue.hour, minute: value.wrappedValue.minute, second: 0, of: Date()) ?? Date() },
            set: { value.wrappedValue = $0.dayTime(.current) }
        ), displayedComponents: .hourAndMinute)
    }
}
