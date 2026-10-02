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
                .frame(minWidth: 960, minHeight: 600)
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
