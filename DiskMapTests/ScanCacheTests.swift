import Foundation
import Testing
@testable import Disk_Map

struct ScanCacheTests {
    let cache = ScanCache(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("DiskMapCacheTests-\(UUID().uuidString)"))

    private func sample() -> ScanResult {
        let root = FileNode(name: "Data", kind: .folder, size: 3_100, children: [
            FileNode(name: "Users", kind: .folder, size: 3_000, children: [
                FileNode(name: "movie.mov", kind: .file, size: 2_000),
                FileNode(name: "", kind: .smallFiles, size: 1_000, fileCount: 42),
            ]),
            FileNode(name: "private", kind: .unreadable, size: 0),
            FileNode(name: "naïve café 📁", kind: .folder, size: 100),
        ])
        root.rootPath = "/System/Volumes/Data"
        return ScanResult(root: root, unreadableCount: 1, date: Date(timeIntervalSince1970: 1_790_000_000))
    }

    private func flatten(_ n: FileNode) -> [String] {
        ["\(n.kind)|\(n.name)|\(n.size)|\(n.fileCount)|\(n.children.count)"] + n.children.flatMap(flatten)
    }

    @Test func roundTripKeepsEverything() throws {
        let original = sample()
        try cache.save(original)
        let loaded = try #require(cache.load(rootPath: "/System/Volumes/Data"))
        #expect(flatten(loaded.root) == flatten(original.root))
        #expect(loaded.unreadableCount == 1)
        #expect(loaded.date == original.date)
        #expect(loaded.root.path == "/System/Volumes/Data")
        #expect(loaded.root.children[0].children[0].path == "/System/Volumes/Data/Users/movie.mov")
    }

    @Test func missingCacheIsNil() {
        #expect(cache.load(rootPath: "/nowhere") == nil)
    }

    @Test func otherVersionOrDamagedFileIsIgnored() throws {
        try cache.save(sample())
        let url = cache.fileURL(for: "/System/Volumes/Data")
        var data = try Data(contentsOf: url)
        data[4] = 99  // bump the version number
        try data.write(to: url)
        #expect(cache.load(rootPath: "/System/Volumes/Data") == nil)

        try cache.save(sample())
        let full = try Data(contentsOf: url)
        try full.prefix(full.count / 2).write(to: url)
        #expect(cache.load(rootPath: "/System/Volumes/Data") == nil)
    }
}
