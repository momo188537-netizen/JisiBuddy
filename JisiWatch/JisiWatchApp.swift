import SwiftUI

@main
struct JisiWatchApp: App {
    @State private var model = WatchModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(model)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.requestSync() }
        }
    }
}
