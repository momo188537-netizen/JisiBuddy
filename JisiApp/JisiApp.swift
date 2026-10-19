import AppIntents
import JisiKit
import SwiftUI

@main
struct JisiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = HomeModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(model)
                .tint(.orange)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { model.onForeground() }
        }
    }
}

/// 让 App 的 App Intents 元数据包含 JisiKit 里的 Intent。
struct JisiAppIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [JisiKitIntents.self] }
}
