import Testing
@testable import Disk_Map

struct FileNodeTests {
    private func sampleTree() -> (root: FileNode, a: FileNode, b: FileNode, big: FileNode) {
        let big = FileNode(name: "big.mov", kind: .file, size: 600)
        let a = FileNode(name: "a", kind: .folder, size: 700, children: [
            big, FileNode(name: "notes.txt", kind: .file, size: 100),
        ])
        let b = FileNode(name: "b", kind: .folder, size: 400, children: [
            FileNode(name: "c.zip", kind: .file, size: 400),
        ])
        let root = FileNode(name: "root", kind: .folder, size: 1100, children: [b, a])
        root.rootPath = "/tmp/root"
        return (root, a, b, big)
    }

    @Test func childrenAreSortedBiggestFirst() {
        let t = sampleTree()
        #expect(t.root.children.map(\.name) == ["a", "b"])
    }

    @Test func pathIsBuiltFromParents() {
        let t = sampleTree()
        #expect(t.big.path == "/tmp/root/a/big.mov")
        #expect(t.root.path == "/tmp/root")
    }

    @Test func removeUpdatesEveryAncestorAndResorts() {
        let t = sampleTree()
        t.a.remove(t.big)
        #expect(t.a.size == 100)
        #expect(t.root.size == 500)
        #expect(t.root.children.map(\.name) == ["b", "a"])
        #expect(t.big.parent == nil)
    }

    @Test func removingANodeThatIsNotAChildDoesNothing() {
        let t = sampleTree()
        t.b.remove(t.big)
        #expect(t.root.size == 1100)
        #expect(t.a.children.count == 2)
    }

    @Test func placeholdersAreNotRealItems() {
        let small = FileNode(name: "", kind: .smallFiles, size: 10, fileCount: 3)
        #expect(!small.isRealItem)
        #expect(small.displayName == "3 small files")
    }
}
