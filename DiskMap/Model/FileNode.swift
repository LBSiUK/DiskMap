import Foundation

/// One entry in a scanned tree: a folder, a file, or a grouped/unreadable placeholder.
final class FileNode: Identifiable, @unchecked Sendable {
    enum Kind: UInt8 {
        case folder = 0
        case file = 1
        case smallFiles = 2   // files below the size threshold, rolled into one entry
        case unreadable = 3   // a folder the scanner wasn't allowed to read
    }

    let name: String
    let kind: Kind
    private(set) var size: Int64
    /// Number of files this node stands for (only meaningful for `.smallFiles`).
    let fileCount: Int
    private(set) var children: [FileNode]
    private(set) weak var parent: FileNode?
    /// Set on the root only: the absolute path the scan started from.
    var rootPath: String?

    var id: ObjectIdentifier { ObjectIdentifier(self) }

    init(name: String, kind: Kind, size: Int64, fileCount: Int = 0, children: [FileNode] = []) {
        self.name = name
        self.kind = kind
        self.size = size
        self.fileCount = fileCount
        self.children = children.sorted { $0.size > $1.size }
        for child in self.children { child.parent = self }
    }

    var isFolder: Bool { kind == .folder }
    /// Placeholders don't exist on disk, so they can't be revealed or deleted.
    var isRealItem: Bool { kind == .folder || kind == .file }

    var displayName: String {
        switch kind {
        case .smallFiles: return fileCount == 1 ? "1 small file" : "\(fileCount.formatted()) small files"
        case .unreadable: return "\(name) (no access)"
        default: return name
        }
    }

    var path: String {
        if let rootPath { return rootPath }
        guard let parent else { return name }
        let base = parent.path
        return base.hasSuffix("/") ? base + name : base + "/" + name
    }

    var url: URL { URL(fileURLWithPath: path) }

    /// The chain from the root down to this node, root first.
    var ancestry: [FileNode] {
        var chain: [FileNode] = []
        var node: FileNode? = self
        while let n = node { chain.append(n); node = n.parent }
        return chain.reversed()
    }

    var root: FileNode { ancestry.first ?? self }

    /// Detaches `child` and subtracts its size from this node and every ancestor,
    /// re-sorting each level so the biggest items stay first.
    func remove(_ child: FileNode) {
        guard let index = children.firstIndex(where: { $0 === child }) else { return }
        children.remove(at: index)
        child.parent = nil
        var node: FileNode? = self
        while let n = node {
            n.size -= child.size
            n.children.sort { $0.size > $1.size }
            node = n.parent
        }
    }
}
