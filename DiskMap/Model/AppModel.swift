import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    // MARK: Locations

    private(set) var locations: [Location]
    private(set) var selectedLocationID: String?

    func select(_ id: String?) {
        guard id != selectedLocationID else { return }
        selectedLocationID = id
        showSelectedLocation()
    }
    var selectedLocation: Location? { locations.first { $0.id == selectedLocationID } }

    // MARK: What's on screen

    private(set) var results: [String: ScanResult] = [:]
    /// Sizes from saved scans that haven't been loaded yet, keyed by path.
    private var savedSizes: [String: Int64] = [:]
    private(set) var current: FileNode?
    private var history: [FileNode] = []
    var hovered: FileNode?
    /// Bumped whenever the tree changes in place, so the treemap knows to redo its layout.
    private(set) var revision = 0
    private(set) var volume: VolumeStats?

    // MARK: Scanning

    private(set) var progress: ScanProgress?
    private(set) var scanStarted: Date?
    private var scanTask: Task<Void, Never>?
    private var scanningPath: String?

    // MARK: Prompts

    private(set) var hasFullDiskAccess = true
    var accessBannerDismissed = false
    var pendingRemoval: PendingRemoval?
    var errorMessage: String?
    var quickLookURL: URL?

    struct PendingRemoval: Identifiable {
        let node: FileNode
        let permanently: Bool
        var id: ObjectIdentifier { node.id }
    }

    private let cache: ScanCache
    private let defaults = UserDefaults.standard
    private static let customKey = "customLocations"

    init(cache: ScanCache = .standard) {
        self.cache = cache
        var all = [Location.startupDisk, Location.home]
        if let data = UserDefaults.standard.data(forKey: Self.customKey),
           let saved = try? JSONDecoder().decode([Location].self, from: data) {
            all += saved
        }
        locations = all
        for location in all { savedSizes[location.path] = cache.savedSize(rootPath: location.path) }
        checkFullDiskAccess()
        selectedLocationID = all.first?.id
        showSelectedLocation()
    }

    // MARK: - Locations

    func addFolder(_ url: URL) {
        let location = Location.custom(url)
        if !locations.contains(where: { $0.id == location.id }) {
            locations.append(location)
            savedSizes[location.path] = cache.savedSize(rootPath: location.path)
            saveCustomLocations()
        }
        select(location.id)
    }

    func removeLocation(_ location: Location) {
        guard location.isCustom else { return }
        locations.removeAll { $0.id == location.id }
        saveCustomLocations()
        if selectedLocationID == location.id { select(locations.first?.id) }
    }

    private func saveCustomLocations() {
        let custom = locations.filter(\.isCustom)
        if let data = try? JSONEncoder().encode(custom) { defaults.set(data, forKey: Self.customKey) }
    }

    private func showSelectedLocation() {
        guard let location = selectedLocation else { current = nil; return }
        if results[location.path] == nil, let cached = cache.load(rootPath: location.path) {
            results[location.path] = cached
        }
        history = []
        hovered = nil
        current = results[location.path]?.root
        volume = VolumeStats(path: location.path)
    }

    var currentResult: ScanResult? { selectedLocation.flatMap { results[$0.path] } }

    /// How much the location held when it was last scanned, or nil if it never has been.
    func scannedSize(of location: Location) -> Int64? {
        results[location.path]?.root.size ?? savedSizes[location.path]
    }

    var isScanningSelected: Bool { progress != nil && scanningPath == selectedLocation?.path }

    // MARK: - Scanning

    func scan() {
        guard let location = selectedLocation else { return }
        stopScan()
        let path = location.path
        let scanner = Scanner(rootPath: path)
        scanningPath = path
        progress = ScanProgress()
        scanStarted = Date()

        let report: @Sendable (ScanProgress) -> Void = { [weak self] p in
            Task { @MainActor in
                if self?.scanningPath == path { self?.progress = p }
            }
        }
        scanTask = Task { [weak self] in
            // The scan runs off the main thread; cancelling this task cancels it too.
            let work = Task.detached(priority: .userInitiated) { try await scanner.run(onProgress: report) }
            do {
                let result = try await withTaskCancellationHandler {
                    try await work.value
                } onCancel: {
                    work.cancel()
                }
                self?.finishScan(result, path: path)
            } catch is CancellationError {
                // Stopped by the user or replaced by a new scan.
            } catch {
                self?.errorMessage = "The scan couldn't finish. \(error.localizedDescription)"
            }
            if self?.scanningPath == path { self?.clearScanState() }
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        clearScanState()
    }

    private func clearScanState() {
        progress = nil
        scanStarted = nil
        scanningPath = nil
    }

    private func finishScan(_ result: ScanResult, path: String) {
        let previousPath = current?.path
        results[path] = result
        let cache = self.cache
        Task.detached(priority: .background) { try? cache.save(result) }
        guard selectedLocation?.path == path else { return }
        // Stay in the same folder if it still exists.
        current = previousPath.flatMap { node(atPath: $0, in: result.root) } ?? result.root
        history = []
        hovered = nil
        volume = VolumeStats(path: path)
        checkFullDiskAccess()
        revision += 1
    }

    private func node(atPath path: String, in root: FileNode) -> FileNode? {
        guard path.hasPrefix(root.path) else { return nil }
        let rest = path.dropFirst(root.path.count).split(separator: "/")
        var node = root
        for part in rest {
            guard let next = node.children.first(where: { $0.isFolder && $0.name == part }) else { return node }
            node = next
        }
        return node
    }

    // MARK: - Navigation

    var canGoBack: Bool { !history.isEmpty }
    var canGoUp: Bool { current?.parent != nil }

    func open(_ node: FileNode) {
        guard node.isFolder, !node.children.isEmpty, node !== current else { return }
        if let current { history.append(current) }
        current = node
        hovered = nil
    }

    func goBack() {
        guard let previous = history.popLast() else { return }
        current = previous
        hovered = nil
    }

    func goUp() {
        guard let parent = current?.parent else { return }
        open(parent)
    }

    // MARK: - Paths

    /// A friendlier spelling of a path: "/System/Volumes/Data/Users/x" becomes "/Users/x"
    /// when that path leads to the same place.
    func displayPath(_ node: FileNode) -> String {
        let path = node.path
        let short = DeleteGuard.normalize(path)
        guard short != path, short != "/" else { return path }
        return FileManager.default.fileExists(atPath: short) ? short : path
    }

    func name(of node: FileNode) -> String {
        node.parent == nil ? (selectedLocation?.name ?? node.name) : node.displayName
    }

    // MARK: - Actions

    func revealInFinder(_ node: FileNode) {
        guard node.isRealItem else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func quickLook(_ node: FileNode) {
        guard node.isRealItem else { return }
        quickLookURL = node.url
    }

    func copyPath(_ node: FileNode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(displayPath(node), forType: .string)
    }

    /// Why this item can't be trashed or deleted, or nil if it can.
    func removalRefusal(for node: FileNode) -> String? {
        switch node.kind {
        case .smallFiles: return "This box stands for many small files, not a single item."
        case .unreadable: return "Disk Map isn't allowed to read this folder."
        default: return DeleteGuard.refusal(for: node.path, scanRoot: node.root.path)
        }
    }

    func requestRemoval(of node: FileNode, permanently: Bool) {
        if let reason = removalRefusal(for: node) {
            errorMessage = reason
            return
        }
        pendingRemoval = PendingRemoval(node: node, permanently: permanently)
    }

    func confirmRemoval() {
        guard let pending = pendingRemoval else { return }
        pendingRemoval = nil
        let node = pending.node
        guard removalRefusal(for: node) == nil, let parent = node.parent else { return }
        let url = node.url
        let permanently = pending.permanently
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    if permanently {
                        try FileManager.default.removeItem(at: url)
                    } else {
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    }
                }.value
                removeFromTree(node, parent: parent)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeFromTree(_ node: FileNode, parent: FileNode) {
        if let current, current.ancestry.contains(where: { $0 === node }) {
            self.current = parent
        }
        history.removeAll { $0.ancestry.contains { $0 === node } }
        if hovered.map({ $0.ancestry.contains { $0 === node } }) == true { hovered = nil }
        parent.remove(node)
        if let location = selectedLocation, let result = results[location.path] {
            let cache = self.cache
            Task.detached(priority: .background) { try? cache.save(result) }
        }
        volume = selectedLocation.flatMap { VolumeStats(path: $0.path) }
        revision += 1
    }

    // MARK: - Full Disk Access

    func checkFullDiskAccess() {
        // These are only readable by apps that have Full Disk Access.
        let probes = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            NSHomeDirectory() + "/Library/Safari/Bookmarks.plist",
        ]
        hasFullDiskAccess = probes.contains { path in
            let fd = Darwin.open(path, O_RDONLY)
            if fd >= 0 { close(fd); return true }
            return false
        }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
