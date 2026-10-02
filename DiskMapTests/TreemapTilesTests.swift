import CoreGraphics
import Testing
@testable import Disk_Map

struct TreemapTilesTests {
    private func tree() -> FileNode {
        func folder(_ name: String, _ kids: [FileNode]) -> FileNode {
            FileNode(name: name, kind: .folder, size: kids.reduce(0) { $0 + $1.size }, children: kids)
        }
        func file(_ name: String, _ size: Int64) -> FileNode { FileNode(name: name, kind: .file, size: size) }
        return folder("root", [
            folder("a", [folder("a1", [folder("a1x", [file("deep", 400)])]), file("a2", 200)]),
            folder("b", [file("b1", 300)]),
            file("c", 100),
            file("empty", 0),
        ])
    }

    let bounds = CGRect(x: 0, y: 0, width: 800, height: 500)

    @Test func tilesStayInsideBoundsAndSkipEmptyItems() {
        let tiles = TreemapTiles.layout(tree(), in: bounds)
        #expect(!tiles.isEmpty)
        #expect(tiles.allSatisfy { bounds.contains($0.rect) })
        #expect(!tiles.contains { $0.node.name == "empty" })
    }

    @Test func nestingStopsAtMaxDepth() {
        let tiles = TreemapTiles.layout(tree(), in: bounds, maxDepth: 3)
        #expect(tiles.map(\.depth).max() == 2)
        #expect(!tiles.contains { $0.node.name == "deep" })
    }

    @Test func childrenShareTheirTopLevelGroup() {
        let tiles = TreemapTiles.layout(tree(), in: bounds)
        let a = tiles.first { $0.node.name == "a" }!
        let a1 = tiles.first { $0.node.name == "a1" }!
        #expect(a.group == a1.group)
        #expect(a.rect.contains(a1.rect))
    }

    @Test func hitFindsTheDeepestTile() {
        let tiles = TreemapTiles.layout(tree(), in: bounds)
        let a1 = tiles.first { $0.node.name == "a1" }!
        let hit = TreemapTiles.hit(tiles, at: CGPoint(x: a1.rect.midX, y: a1.rect.midY))
        #expect(hit.map { $0.depth >= 1 } == true)
        #expect(TreemapTiles.hit(tiles, at: CGPoint(x: -5, y: -5)) == nil)
    }

    @Test func tinyBoundsGiveNoTiles() {
        #expect(TreemapTiles.layout(tree(), in: CGRect(x: 0, y: 0, width: 2, height: 2)).isEmpty)
    }
}
