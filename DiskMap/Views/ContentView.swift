import QuickLook
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(Updater.self) private var updater
    @State private var showInspector = true

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
        } detail: {
            detail
                .inspector(isPresented: $showInspector) {
                    InspectorView()
                        .inspectorColumnWidth(min: 260, ideal: 320, max: 480)
                }
        }
        .navigationTitle(model.selectedLocation?.name ?? "Disk Map")
        .navigationSubtitle(model.current.flatMap { $0.parent == nil ? nil : model.displayPath($0) } ?? "")
        .toolbar { toolbar }
        .toolbarTitleMenu {
            if let current = model.current {
                ForEach(current.ancestry.reversed().dropFirst(), id: \.id) { folder in
                    Button(model.name(of: folder), systemImage: "folder") { model.open(folder) }
                }
            }
        }
        .quickLookPreview($model.quickLookURL)
        .alert(item: $model.pendingRemoval) { pending in
            removalAlert(pending)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.checkFullDiskAccess()
        }
    }

    @ViewBuilder private var detail: some View {
        VStack(spacing: 0) {
            if let release = updater.availableRelease ?? updater.installingRelease, !updater.bannerDismissed {
                UpdateBanner(release: release)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
            if !model.hasFullDiskAccess && !model.accessBannerDismissed {
                AccessBanner()
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
            if model.currentResult != nil {
                VolumeSummary()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            ZStack {
                if model.current != nil {
                    TreemapView()
                        .padding(.horizontal, 12)
                } else if !model.isScanningSelected {
                    ContentUnavailableView {
                        Label("No scan yet", systemImage: "square.grid.3x3.topleft.filled")
                    } description: {
                        Text("Scan \(model.selectedLocation?.name ?? "this location") to see what's using the space.")
                    } actions: {
                        Button("Scan Now") { model.scan() }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if model.isScanningSelected, let progress = model.progress {
                    ScanCapsule(progress: progress)
                        .padding(.top, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.isScanningSelected)
            if model.current != nil {
                HoverBar()
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Back", systemImage: "chevron.backward") { model.goBack() }
                .disabled(!model.canGoBack)
                .keyboardShortcut("[", modifiers: .command)
            Button("Up", systemImage: "chevron.up") { model.goUp() }
                .disabled(!model.canGoUp)
                .keyboardShortcut(.upArrow, modifiers: .command)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.scan()
            } label: {
                Label(model.currentResult == nil ? "Scan" : "Update", systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.glassProminent)
            .disabled(model.isScanningSelected)
            .keyboardShortcut("r", modifiers: .command)
            .help("Scan this location again")
        }
        ToolbarSpacer(.fixed)
        ToolbarItem(placement: .primaryAction) {
            Button("Inspector", systemImage: "sidebar.trailing") { showInspector.toggle() }
                .help("Show or hide the list")
        }
    }

    private func removalAlert(_ pending: AppModel.PendingRemoval) -> Alert {
        let name = model.name(of: pending.node)
        let size = pending.node.size.bytes
        if pending.permanently {
            return Alert(
                title: Text("Delete “\(name)” permanently?"),
                message: Text("This frees \(size) straight away. It won't go to the Trash and can't be undone."),
                primaryButton: .destructive(Text("Delete Permanently")) { model.confirmRemoval() },
                secondaryButton: .cancel())
        }
        return Alert(
            title: Text("Move “\(name)” to the Trash?"),
            message: Text("It takes up \(size). The space comes back once you empty the Trash."),
            primaryButton: .default(Text("Move to Trash")) { model.confirmRemoval() },
            secondaryButton: .cancel())
    }
}
