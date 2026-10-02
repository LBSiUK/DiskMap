import SwiftUI

/// A one-line bar under the map describing whatever is under the pointer.
/// It sits below the map rather than over it, so it never hides any boxes.
struct HoverBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            if let node = model.hovered {
                let total = model.volume?.total ?? node.root.size
                let share = total > 0 ? Double(node.size) / Double(total) : 0
                Text(model.name(of: node)).fontWeight(.semibold).lineLimit(1)
                Text(node.size.bytes).monospacedDigit()
                Text("\(share.formatted(.percent.precision(.fractionLength(2)))) of the disk")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if node.isRealItem {
                    Text(model.displayPath(node))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                Text("Point at a box to see what it is. Click to zoom in, right-click for more.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .frame(height: 32)
    }
}

/// Shows scan progress over the map, with a way to stop.
struct ScanCapsule: View {
    @Environment(AppModel.self) private var model
    let progress: ScanProgress

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = Int(context.date.timeIntervalSince(model.scanStarted ?? context.date))
                Text("Scanning · \(progress.folders.formatted()) folders · \(progress.bytes.bytes) · \(seconds)s")
                    .monospacedDigit()
            }
            Button("Stop") { model.stopScan() }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Explains that some folders are hidden without Full Disk Access.
struct AccessBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Some folders are hidden").font(.headline)
                Text("Give Disk Map Full Disk Access for complete numbers, then scan again.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Open Settings") { model.openFullDiskAccessSettings() }
                .buttonStyle(.glassProminent)
            Button {
                model.accessBannerDismissed = true
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .help("Hide")
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

/// Used, free and scanned space for the location's volume.
struct VolumeSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let scanned = model.currentResult?.root.size ?? 0
        HStack(spacing: 14) {
            if let volume = model.volume {
                let other = max(volume.used - scanned, 0)
                GeometryReader { geo in
                    let w = geo.size.width
                    let total = Double(max(volume.total, 1))
                    HStack(spacing: 2) {
                        Capsule().fill(Color.accentColor)
                            .frame(width: w * Double(min(scanned, volume.used)) / total)
                            .help("Found by the scan: \(scanned.bytes)")
                        Capsule().fill(Color.secondary.opacity(0.5))
                            .frame(width: w * Double(other) / total)
                            .help("Snapshots, hidden folders and other volumes: \(other.bytes)")
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity)
                    .background(Capsule().fill(.quaternary))
                }
                .frame(height: 8)
                Text("\(volume.used.bytes) used · \(volume.available.bytes) free")
                    .monospacedDigit()
                    .fixedSize()
            }
            if let date = model.currentResult?.date {
                Text("Scanned \(date.formatted(.relative(presentation: .named)))")
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .font(.callout)
    }
}

/// Tells the user a newer version is out, with a one-click update.
struct UpdateBanner: View {
    @Environment(Updater.self) private var updater
    let release: Release

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Disk Map \(release.version) is available").font(.headline)
                Text(updater.state == .readyToRelaunch
                     ? "Downloaded and ready. Disk Map will reopen on the new version."
                     : "You have \(updater.currentVersion). This'll only take a minute!")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            switch updater.state {
            case .downloading(let fraction):
                ProgressView(value: fraction).frame(width: 120)
            case .installing:
                ProgressView().controlSize(.small)
            case .readyToRelaunch:
                Button("Relaunch to update") { updater.relaunchToUpdate() }
                    .buttonStyle(.glassProminent)
                    .tint(.blue)
            default:
                Button("What's New") { NSWorkspace.shared.open(release.htmlURL) }
                    .buttonStyle(.glass)
                Button("Install Update") { Task { await updater.install(release) } }
                    .buttonStyle(.glassProminent)
                Button {
                    updater.bannerDismissed = true
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("Hide")
            }
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}
