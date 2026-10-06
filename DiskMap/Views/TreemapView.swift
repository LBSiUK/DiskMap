import SwiftUI

/// Draws the current folder as nested boxes in a single Canvas.
struct TreemapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var cache = TileCache()

    var body: some View {
        GeometryReader { geo in
            let bounds = CGRect(origin: .zero, size: geo.size).insetBy(dx: 1, dy: 1)
            let tiles = cache.tiles(for: model.current, revision: model.revision, bounds: bounds)
            let palette = Palette.current(scheme)
            let hovered = model.hovered

            Canvas { context, _ in
                for tile in tiles { draw(tile, palette: palette, in: &context) }
                if let hovered, let tile = tiles.last(where: { $0.node === hovered }) {
                    let outline = RoundedRectangle(cornerRadius: 3).path(in: tile.rect.insetBy(dx: 1, dy: 1))
                    context.stroke(outline, with: .color(palette.ink), lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): model.hovered = TreemapTiles.hit(tiles, at: point)?.node
                case .ended: model.hovered = nil
                }
            }
            .onTapGesture(count: 1, coordinateSpace: .local) { point in
                // Zoom into the top-level box that was clicked, like stepping into a folder.
                guard let hit = TreemapTiles.hit(tiles, at: point) else { return }
                if let top = tiles.last(where: { $0.depth == 0 && $0.rect.contains(point) }), top.node.isFolder {
                    model.open(top.node)
                } else if hit.node.isFolder {
                    model.open(hit.node)
                }
            }
            .contextMenu {
                if let node = model.hovered { NodeMenu(node: node) }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            guard let node = model.hovered, node.isRealItem else { return .ignored }
            model.quickLook(node)
            return .handled
        }
        .accessibilityLabel("Treemap of \(model.current.map { model.name(of: $0) } ?? "nothing")")
    }

    private func draw(_ tile: Tile, palette: Palette, in context: inout GraphicsContext) {
        let placeholder = !tile.node.isRealItem
        let shape = RoundedRectangle(cornerRadius: 3).path(in: tile.rect)
        context.fill(shape, with: .color(palette.fill(group: tile.group, depth: tile.depth, placeholder: placeholder)))

        if placeholder {
            // Diagonal hatching marks grouped small files and folders that couldn't be read.
            var inner = context
            inner.clip(to: shape)
            var lines = Path()
            let r = tile.rect
            var x = r.minX - r.height
            while x < r.maxX {
                lines.move(to: CGPoint(x: x, y: r.maxY))
                lines.addLine(to: CGPoint(x: x + r.height, y: r.minY))
                x += 7
            }
            inner.stroke(lines, with: .color(palette.ink.opacity(0.12)), lineWidth: 2)
        }

        guard tile.showsLabel, tile.rect.width > 44, tile.rect.height > 18 else { return }
        let name = model.name(of: tile.node)
        let size = tile.node.size.bytes
        let room = Int((tile.rect.width - 10) / 6.4)
        let label: Text
        if name.count + size.count + 1 <= room {
            label = Text("\(Text(name).fontWeight(.semibold)) \(Text(size).foregroundStyle(palette.ink.opacity(0.7)))")
        } else {
            label = Text(truncate(name, to: room)).fontWeight(.semibold)
        }
        context.draw(label.font(.system(size: 11)).foregroundStyle(palette.ink),
                     at: CGPoint(x: tile.rect.minX + 5, y: tile.rect.minY + 3), anchor: .topLeading)
    }

    private func truncate(_ s: String, to count: Int) -> String {
        guard s.count > count else { return s }
        return count > 1 ? String(s.prefix(count - 1)) + "…" : ""
    }
}

/// Remembers the last layout so hovering doesn't redo it on every mouse move.
final class TileCache {
    private var key: (ObjectIdentifier?, Int, CGRect)?
    private var cached: [Tile] = []

    func tiles(for folder: FileNode?, revision: Int, bounds: CGRect) -> [Tile] {
        guard let folder else { return [] }
        if let key, key.0 == folder.id, key.1 == revision, key.2 == bounds { return cached }
        cached = TreemapTiles.layout(folder, in: bounds)
        key = (folder.id, revision, bounds)
        return cached
    }
}
