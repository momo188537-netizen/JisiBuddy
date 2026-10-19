import AppIntents
import JisiKit
import SwiftUI
import WidgetKit

/// 控制中心 / 锁屏底部 / 操作按钮可放的「鸡丝上班」开关。
@available(iOS 18.0, *)
struct JisiWorkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: LiveActivityController.controlKind, provider: WorkValueProvider()) { isWorking in
            ControlWidgetToggle("鸡丝上班", isOn: isWorking, action: SetWorkingIntent()) { on in
                Label(on ? "上班中" : "在家", systemImage: on ? "briefcase.fill" : "house.fill")
            }
            .tint(.orange)
        }
        .displayName("带鸡丝上班")
        .description("打开：带鸡丝上班；关掉：一起下班。")
    }
}

@available(iOS 18.0, *)
struct WorkValueProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        SharedStore.shared.session?.isOpen ?? false
    }
}
