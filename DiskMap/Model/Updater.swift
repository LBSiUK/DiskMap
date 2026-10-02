import AppKit
import Foundation
import Observation

/// A published release on GitHub.
struct Release: Decodable, Equatable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let assets: [Asset]

    struct Asset: Decodable, Equatable {
        let name: String
        let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", name, body, htmlURL = "html_url", assets
    }

    /// "v1.2.0" becomes "1.2.0".
    var version: String { tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName }
    var dmg: Asset? { assets.first { $0.name.lowercased().hasSuffix(".dmg") } }
}

enum Versions {
    /// True when `candidate` is a later version than `current`, comparing numbers part by part
    /// ("1.10" is newer than "1.9", "1.2" equals "1.2.0").
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            let trimmed = v.hasPrefix("v") ? String(v.dropFirst()) : v
            return trimmed.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// Checks GitHub for a newer release and can install it in place.
@MainActor
@Observable
final class Updater {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Double)
        case installing          // checking the download and getting it ready
        case readyToRelaunch     // the new version is waiting; relaunching swaps it in
        case failed(String)
    }

    static let repository = "LBSiUK/DiskMap"
    static let checkOnLaunchKey = "checkForUpdatesOnLaunch"
    private static let lastCheckKey = "lastUpdateCheck"
    /// Lets a test point the app at a local feed instead of GitHub.
    private static let feedOverrideKey = "DiskMapUpdateFeed"

    private(set) var state: State = .idle
    var bannerDismissed = false
    private(set) var lastCheck: Date?

    let currentVersion: String
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard,
         currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0") {
        self.defaults = defaults
        self.currentVersion = currentVersion
        defaults.register(defaults: [Self.checkOnLaunchKey: true])
        lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
    }

    var availableRelease: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    /// The release being downloaded or installed, so the banner can show progress.
    private(set) var installingRelease: Release?

    var releasesPage: URL { URL(string: "https://github.com/\(Self.repository)/releases")! }

    private var feedURL: URL {
        if let override = defaults.string(forKey: Self.feedOverrideKey), let url = URL(string: override) { return url }
        return URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
    }

    func checkOnLaunchIfEnabled() {
        if defaults.bool(forKey: Self.checkOnLaunchKey) { Task { await check(quietly: true) } }
    }

    /// Asks GitHub for the latest release. A quiet check doesn't report network problems,
    /// so a launch without internet stays silent.
    func check(quietly: Bool = false) async {
        if case .downloading = state { return }
        if state == .installing || state == .readyToRelaunch { return }
        state = .checking
        do {
            var request = URLRequest(url: feedURL, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                state = .upToDate  // no releases published yet
            } else {
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                let release = try JSONDecoder().decode(Release.self, from: data)
                if Versions.isNewer(release.version, than: currentVersion) {
                    bannerDismissed = false
                    state = .available(release)
                } else {
                    state = .upToDate
                }
            }
            lastCheck = Date()
            defaults.set(lastCheck, forKey: Self.lastCheckKey)
        } catch {
            state = quietly ? .idle : .failed("Couldn't reach GitHub. \(error.localizedDescription)")
        }
    }

    /// The menu's Check for Updates: says so out loud when there's nothing new or it fails.
    /// A newer version shows the banner in the main window instead.
    func checkFromMenu() async {
        await check()
        let alert = NSAlert()
        switch state {
        case .upToDate:
            alert.messageText = "Disk Map is up to date"
            alert.informativeText = "You have the latest version, \(currentVersion)."
        case .failed(let message):
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = message
        default:
            return
        }
        alert.runModal()
    }

    // MARK: - Installing

    /// The checked copy of the new version, waiting to replace this one.
    private var preparedApp: URL?

    /// Downloads the release's DMG and gets the new version ready. Nothing changes until
    /// `relaunchToUpdate()` is called.
    func install(_ release: Release) async {
        guard let asset = release.dmg else {
            NSWorkspace.shared.open(release.htmlURL)
            return
        }
        let appURL = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path),
              !appURL.path.hasPrefix("/Volumes/") else {
            // Running from the DMG or somewhere we can't write: let the user install by hand.
            state = .failed("Disk Map can't update itself from here. Move it to Applications first, or download the update yourself.")
            return
        }

        installingRelease = release
        state = .downloading(0)
        do {
            let dmg = try await download(asset.browserDownloadURL)
            state = .installing
            preparedApp = try await Task.detached { try Self.extractApp(from: dmg, expectedVersion: release.version) }.value
            state = .readyToRelaunch
        } catch {
            installingRelease = nil
            state = .failed("The update didn't install. \(error.localizedDescription)")
        }
    }

    /// Swaps in the downloaded version and reopens the app.
    func relaunchToUpdate() {
        guard state == .readyToRelaunch, let preparedApp else { return }
        let appURL = Bundle.main.bundleURL
        do {
            _ = try FileManager.default.replaceItemAt(appURL, withItemAt: preparedApp)
            relaunch(appURL)
        } catch {
            self.preparedApp = nil
            installingRelease = nil
            state = .failed("The update didn't install. \(error.localizedDescription)")
        }
    }

    private func download(_ url: URL) async throws -> URL {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let total = max(response.expectedContentLength, 1)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("DiskMapUpdate-\(UUID().uuidString).dmg")
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var buffer = Data()
        buffer.reserveCapacity(1 << 20)
        var received: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 20 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                state = .downloading(min(Double(received) / Double(total), 1))
            }
        }
        try handle.write(contentsOf: buffer)
        return destination
    }

    /// Mounts the DMG, checks the app inside is Disk Map at the expected version and properly
    /// signed, and copies it to a temporary folder on the same disk as the installed app.
    nonisolated private static func extractApp(from dmg: URL, expectedVersion: String) throws -> URL {
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("DiskMapMount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        defer {
            _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            try? FileManager.default.removeItem(at: dmg)
        }

        let contents = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
        guard let app = contents.first(where: { $0.pathExtension == "app" }),
              let info = Bundle(url: app)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == expectedVersion
        else { throw CocoaError(.fileReadCorruptFile) }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])

        let staging = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                  appropriateFor: Bundle.main.bundleURL, create: true)
        let copy = staging.appendingPathComponent(app.lastPathComponent)
        try FileManager.default.copyItem(at: app, to: copy)
        return copy
    }

    @discardableResult
    nonisolated private static func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "DiskMap.Updater", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\((tool as NSString).lastPathComponent) failed."])
        }
        return process.terminationStatus
    }

    private func relaunch(_ appURL: URL) {
        let script = Process()
        script.executableURL = URL(fileURLWithPath: "/bin/sh")
        script.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", appURL.path]
        try? script.run()
        NSApp.terminate(nil)
    }
}
