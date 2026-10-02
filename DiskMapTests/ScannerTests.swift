import Foundation
import Testing
@testable import Disk_Map

/// Builds a throwaway folder tree and checks the scanner's totals against `stat`.
final class TempTree {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DiskMapTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        // Give back permissions first so the unreadable folder can be removed.
        chmod(root.appendingPathComponent("locked").path, 0o755)
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func file(_ relative: String, bytes: Int) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    func folder(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Space the file really takes up on disk, the same measure the scanner uses.
    static func allocated(_ url: URL) -> Int64 {
        var st = stat()
        lstat(url.path, &st)
        return Int64(st.st_blocks) * 512
    }
}

struct ScannerTests {
    @Test func totalsMatchAllocatedSizes() async throws {
        let tree = try TempTree()
        let a = try tree.file("a/big.bin", bytes: 3_000_000)
        let b = try tree.file("a/deep/er/also.bin", bytes: 1_500_000)
        let c = try tree.file("note.txt", bytes: 1_000)
        let expected = [a, b, c].map(TempTree.allocated).reduce(0, +)

        let result = try await Scanner(rootPath: tree.root.path, smallFileThreshold: 1_000_000).run()
        #expect(result.root.size == expected)
        #expect(result.root.path == tree.root.path)
        let folderA = try #require(result.root.children.first { $0.name == "a" })
        #expect(folderA.children.contains { $0.name == "big.bin" && $0.kind == .file })
    }

    @Test func smallFilesAreGroupedPerFolder() async throws {
        let tree = try TempTree()
        for i in 0..<5 { try tree.file("docs/n\(i).txt", bytes: 2_000) }
        try tree.file("docs/large.bin", bytes: 2_000_000)

        let result = try await Scanner(rootPath: tree.root.path, smallFileThreshold: 1_000_000).run()
        let docs = try #require(result.root.children.first { $0.name == "docs" })
        let group = try #require(docs.children.first { $0.kind == .smallFiles })
        #expect(group.fileCount == 5)
        #expect(docs.children.filter { $0.kind == .file }.map(\.name) == ["large.bin"])
    }

    @Test func hardLinksAreCountedOnce() async throws {
        let tree = try TempTree()
        let original = try tree.file("one/video.mov", bytes: 2_000_000)
        _ = try tree.folder("two")
        try FileManager.default.linkItem(at: original, to: tree.root.appendingPathComponent("two/video.mov"))

        let result = try await Scanner(rootPath: tree.root.path).run()
        #expect(result.root.size == TempTree.allocated(original))
    }

    @Test func symbolicLinksAreNotFollowed() async throws {
        let tree = try TempTree()
        let outside = try TempTree()
        try outside.file("huge.bin", bytes: 4_000_000)
        try FileManager.default.createSymbolicLink(at: tree.root.appendingPathComponent("link"),
                                                   withDestinationURL: outside.root)

        let result = try await Scanner(rootPath: tree.root.path).run()
        #expect(result.root.size < 1_000_000)
    }

    @Test func unreadableFoldersAreReportedAndScanCarriesOn() async throws {
        let tree = try TempTree()
        try tree.file("locked/secret.bin", bytes: 2_000_000)
        let fine = try tree.file("fine/data.bin", bytes: 2_000_000)
        chmod(tree.root.appendingPathComponent("locked").path, 0o000)

        let result = try await Scanner(rootPath: tree.root.path).run()
        #expect(result.unreadableCount == 1)
        #expect(result.root.children.contains { $0.kind == .unreadable && $0.name == "locked" })
        #expect(result.root.size == TempTree.allocated(fine))
    }

    @Test func emptyFolderScansToZero() async throws {
        let tree = try TempTree()
        let result = try await Scanner(rootPath: tree.root.path).run()
        #expect(result.root.size == 0)
        #expect(result.root.children.isEmpty)
    }

    @Test func missingRootThrows() async {
        await #expect(throws: (any Error).self) {
            try await Scanner(rootPath: "/definitely/not/here").run()
        }
    }
}

struct ScannerCancellationTests {
    @Test func cancellingStopsTheScan() async throws {
        let tree = try TempTree()
        for i in 0..<200 { _ = try tree.folder("f\(i)/a/b/c") }
        let task = Task { try await Scanner(rootPath: tree.root.path).run() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func unreadableRootThrows() async throws {
        let tree = try TempTree()
        let locked = try tree.folder("locked")
        chmod(locked.path, 0o000)
        await #expect(throws: CocoaError.self) { try await Scanner(rootPath: locked.path).run() }
    }
}
