import JisiKit
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
                Section("工作日") {
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
                }
                Section {
                    Toggle("饭点提醒", isOn: $model.reminders.mealsEnabled)
                    Toggle("休息提醒", isOn: $model.reminders.breaksEnabled)
                    if model.reminders.breaksEnabled {
                        Stepper("每 \(model.reminders.breakInterval) 分钟", value: $model.reminders.breakInterval, in: 30...180, step: 15)
                    }
                } header: {
                    Text("提醒")
                } footer: {
                    Text("提醒里可以直接点「吃了」「休息了」，鸡丝会知道。不点也没关系。")
                }
                BackupSection()

                #if DEBUG
                Section("调试") {
                    Button("1 分钟后发一条测试饭点提醒") {
                        Task { await Reminders.shared.sendTestMeal() }
                    }
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
