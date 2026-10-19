import AppIntents
import JisiKit
import SwiftUI
import WidgetKit

@main
struct JisiWidgetsBundle: WidgetBundle {
    var body: some Widget {
        JisiLockScreenWidget()
        JisiLiveActivity()
    }
}

/// 让扩展的 App Intents 元数据包含 JisiKit 里的 Intent（Live Activity 按钮要用）。
struct JisiWidgetsIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [JisiKitIntents.self] }
}
