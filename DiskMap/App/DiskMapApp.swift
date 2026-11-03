import SwiftUI

@main
struct DiskMapApp: App {
    @State private var model = AppModel()
    @State private var updater = Updater()

    var body: some Scene {
        Window("Disk Map", id: "main") {
            ContentView()
                .environment(model)
                .environment(updater)
                // No minWidth here. The split view works out its own, and a smaller one here
                // makes macOS 27 redo the layout forever until the app crashes.
                .frame(minHeight: 600)
                .task { updater.checkOnLaunchIfEnabled() }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About Disk Map") { AppInfo.showAboutPanel() }
                Button("Check for Updates…") { Task { await updater.checkFromMenu() } }
            }
        }

        Settings {
            SettingsView()
                .environment(updater)
        }
    }
}
