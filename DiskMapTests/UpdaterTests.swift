import Foundation
import Testing
@testable import Disk_Map

struct VersionTests {
    @Test(arguments: [("0.2.0", "0.1.0"), ("1.10", "1.9"), ("v1.0.1", "1.0"), ("2", "1.9.9"), ("0.1.1", "0.1")])
    func newerVersionsAreSpotted(pair: (String, String)) {
        #expect(Versions.isNewer(pair.0, than: pair.1))
    }

    @Test(arguments: [("0.1.0", "0.1.0"), ("1.2", "1.2.0"), ("0.9", "0.10"), ("v0.1.0", "0.1.0")])
    func sameOrOlderVersionsAreNot(pair: (String, String)) {
        #expect(!Versions.isNewer(pair.0, than: pair.1))
    }
}

struct ReleaseTests {
    let json = """
    {
      "tag_name": "v0.2.0",
      "name": "Disk Map 0.2.0",
      "body": "Faster scans.",
      "html_url": "https://github.com/LBSiUK/DiskMap/releases/tag/v0.2.0",
      "assets": [
        {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"},
        {"name": "DiskMap-0.2.0.dmg", "browser_download_url": "https://example.com/DiskMap-0.2.0.dmg"}
      ],
      "draft": false
    }
    """

    @Test func decodesGitHubRelease() throws {
        let release = try JSONDecoder().decode(Release.self, from: Data(json.utf8))
        #expect(release.version == "0.2.0")
        #expect(release.dmg?.name == "DiskMap-0.2.0.dmg")
        #expect(release.htmlURL.absoluteString.hasSuffix("v0.2.0"))
    }

    @MainActor @Test func checkFindsNewerReleaseFromFeed() async throws {
        let feed = FileManager.default.temporaryDirectory.appendingPathComponent("feed-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: feed)
        let defaults = try #require(UserDefaults(suiteName: "UpdaterTests-\(UUID().uuidString)"))
        defaults.set(feed.absoluteString, forKey: "DiskMapUpdateFeed")

        let older = Updater(defaults: defaults, currentVersion: "0.1.0")
        await older.check()
        #expect(older.availableRelease?.version == "0.2.0")
        #expect(older.lastCheck != nil)

        let same = Updater(defaults: defaults, currentVersion: "0.2.0")
        await same.check()
        #expect(same.state == .upToDate)
    }

    @MainActor @Test func unreachableFeedFailsOnlyWhenNotQuiet() async throws {
        let defaults = try #require(UserDefaults(suiteName: "UpdaterTests-\(UUID().uuidString)"))
        defaults.set("file:///definitely/missing.json", forKey: "DiskMapUpdateFeed")
        let updater = Updater(defaults: defaults, currentVersion: "0.1.0")
        await updater.check(quietly: true)
        #expect(updater.state == .idle)
        await updater.check()
        if case .failed = updater.state {} else { Issue.record("expected a failure") }
    }
}
