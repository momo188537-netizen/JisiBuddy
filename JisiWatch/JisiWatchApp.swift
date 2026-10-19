import SwiftUI

@main
struct JisiWatchApp: App {
    @State private var model = WatchModel.shared

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(model)
        }
    }
}
