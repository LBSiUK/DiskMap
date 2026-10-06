import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var choosingFolder = false

    var body: some View {
        let selection = Binding<String?>(get: { model.selectedLocationID }, set: { model.select($0) })

        List(selection: selection) {
            Section("Locations") {
                ForEach(model.locations) { location in
                    LocationRow(location: location, scannedSize: model.scannedSize(of: location))
                        .tag(location.id)
                        .contextMenu {
                            if location.isCustom {
                                Button("Remove from Sidebar", systemImage: "minus.circle") { model.removeLocation(location) }
                            }
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Choose Folder…", systemImage: "folder.badge.plus") { choosingFolder = true }
                .buttonStyle(.glass)
                .padding(12)
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.addFolder(url) }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220)
    }
}

private struct LocationRow: View {
    let location: Location
    let scannedSize: Int64?

    var body: some View {
        let volume = VolumeStats(path: location.path)
        VStack(alignment: .leading, spacing: 4) {
            Label(location.name, systemImage: location.symbol)
            Group {
                if !location.isCustom, location.symbol == "internaldrive", let volume {
                    ProgressView(value: Double(volume.used), total: Double(max(volume.total, 1)))
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                    Text("\(volume.available.bytes) free of \(volume.total.bytes)")
                } else if let scannedSize {
                    Text(scannedSize.bytes)
                } else {
                    Text("Not scanned yet")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 26)
        }
        .padding(.vertical, 2)
    }
}
