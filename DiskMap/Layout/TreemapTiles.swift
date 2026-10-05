import CoreGraphics

/// One box on the treemap.
struct Tile {
    let node: FileNode
    let rect: CGRect
    /// 0 for children of the folder being shown, 1 for their children, and so on.
    let depth: Int
    /// Which child of the shown folder this tile sits under; picks its colour.
    let group: Int
    /// Folders big enough to hold children get a strip at the top for their name.
    let hasHeader: Bool
    /// False when the box's children fill it edge to edge and would paint over its name.
    let showsLabel: Bool
}

enum TreemapTiles {
    static let maxDepth = 3
    static let minSide: CGFloat = 3
    static let headerHeight: CGFloat = 16
    static let padding: CGFloat = 2
    static let gap: CGFloat = 2

    /// Lays out `folder`'s children inside `bounds`, nesting up to `maxDepth` levels.
    /// Parents come before their children, so drawing in order paints children on top.
    static func layout(_ folder: FileNode, in bounds: CGRect, maxDepth: Int = maxDepth) -> [Tile] {
        var tiles: [Tile] = []
        let children = folder.children.filter { $0.size > 0 }
        let rects = squarify(children.map { Double($0.size) }, in: bounds)
        for (index, (child, rect)) in zip(children, rects).enumerated() {
            place(child, in: rect, depth: 0, group: index, maxDepth: maxDepth, into: &tiles)
        }
        return tiles
    }

    private static func place(_ node: FileNode, in slot: CGRect, depth: Int, group: Int, maxDepth: Int, into tiles: inout [Tile]) {
        let rect = slot.insetBy(dx: gap / 2, dy: gap / 2)
        guard rect.width >= minSide, rect.height >= minSide else { return }

        let showsHeader = node.isFolder && rect.height > 34 && rect.width > 60
        let inner = CGRect(x: rect.minX + padding,
                           y: rect.minY + padding + (showsHeader ? headerHeight : 0),
                           width: rect.width - padding * 2,
                           height: rect.height - padding * 2 - (showsHeader ? headerHeight : 0))
        let nests = node.isFolder && depth + 1 < maxDepth && inner.width > 20 && inner.height > 20
        tiles.append(Tile(node: node, rect: rect, depth: depth, group: group,
                          hasHeader: showsHeader && nests, showsLabel: showsHeader || !nests))

        guard nests else { return }
        let children = node.children.filter { $0.size > 0 }
        let rects = squarify(children.map { Double($0.size) }, in: inner)
        for (child, childRect) in zip(children, rects) {
            place(child, in: childRect, depth: depth + 1, group: group, maxDepth: maxDepth, into: &tiles)
        }
    }

    /// The deepest tile under `point`, if any.
    static func hit(_ tiles: [Tile], at point: CGPoint) -> Tile? {
        tiles.last { $0.rect.contains(point) }
    }
}
