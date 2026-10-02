import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Updates", systemImage: "arrow.down.circle") { UpdatesSettings() }
            Tab("About", systemImage: "info.circle") { AboutSettings() }
        }
        .frame(width: 460)
        .scenePadding()
    }
}

private struct UpdatesSettings: View {
    @Environment(Updater.self) private var updater
    @AppStorage(Updater.checkOnLaunchKey) private var checkOnLaunch = true

    var body: some View {
        Form {
            Section {
                Toggle("Check for updates when Disk Map opens", isOn: $checkOnLaunch)
                LabeledContent("Installed version", value: updater.currentVersion)
                LabeledContent("Last checked") {
                    if let date = updater.lastCheck {
                        Text(date.formatted(.relative(presentation: .named)))
                    } else {
                        Text("Never")
                    }
                }
            } footer: {
                Text("Disk Map asks GitHub for the latest release. Nothing about your files is sent.")
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    status
                    Spacer()
                    if updater.state == .readyToRelaunch {
                        Button("Relaunch to update") { updater.relaunchToUpdate() }
                            .buttonStyle(.glassProminent)
                            .tint(.blue)
                    } else if let release = updater.availableRelease {
                        Button("Update to \(release.version)") { Task { await updater.install(release) } }
                            .buttonStyle(.glassProminent)
                    } else {
                        Button("Check Now") { Task { await updater.check() } }
                            .disabled(updater.state == .checking)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var status: some View {
        switch updater.state {
        case .idle: Text("Not checked yet").foregroundStyle(.secondary)
        case .checking: HStack { ProgressView().controlSize(.small); Text("Checking…") }
        case .upToDate: Label("Disk Map is up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .available(let release): Label("Version \(release.version) is available", systemImage: "sparkles")
        case .downloading(let fraction): ProgressView("Downloading…", value: fraction).frame(maxWidth: 220)
        case .installing: HStack { ProgressView().controlSize(.small); Text("Getting it ready…") }
        case .readyToRelaunch: Label("Downloaded and ready to install", systemImage: "checkmark.circle.fill").foregroundStyle(.blue)
        case .failed(let message): Text(message).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Disk Map").font(.title2.bold())
            Text("Version \(AppInfo.version)").foregroundStyle(.secondary)
            Text(AppInfo.copyright).font(.callout)
            Link("github.com/LBSiUK/DiskMap", destination: AppInfo.website)
                .font(.callout)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
