import AppIntents
import JisiKit

/// Siri / 快捷指令里直接可用的动作。
struct JisiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartWorkIntent(),
            phrases: ["带\(.applicationName)上班", "和\(.applicationName)一起上班", "\(.applicationName)上班"],
            shortTitle: "带鸡丝上班",
            systemImageName: "briefcase.fill"
        )
        AppShortcut(
            intent: ClockOutShortcutIntent(),
            phrases: ["和\(.applicationName)一起下班", "\(.applicationName)下班"],
            shortTitle: "一起下班",
            systemImageName: "house.fill"
        )
        AppShortcut(
            intent: StartMeetingIntent(),
            phrases: ["\(.applicationName)我在开会", "告诉\(.applicationName)我在开会"],
            shortTitle: "我在开会",
            systemImageName: "bell.slash.fill"
        )
    }
}
