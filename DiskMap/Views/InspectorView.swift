import SwiftUI

/// The list on the right: what's in the current folder, biggest first.
struct InspectorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let folder = model.current {
            let palette = Palette.current(scheme)
            let children = folder.children
            List {
                Section {
                    ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                        Row(node: child,
                            name: model.name(of: child),
                            share: folder.size > 0 ? Double(child.size) / Double(folder.size) : 0,
                            color: child.isRealItem ? palette.swatch(group: index) : palette.other,
                            isHovered: model.hovered === child)
                            .contentShape(Rectangle())
                            .onTapGesture { model.open(child) }
                            .onHover { inside in
                                if inside { model.hovered = child } else if model.hovered === child { model.hovered = nil }
                            }
                            .contextMenu { NodeMenu(node: child) }
                    }
                } header: {
                    HStack {
                        Text(model.name(of: folder)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(folder.size.bytes).monospacedDigit()
                    }
                }
            }
            .id(ObjectIdentifier(folder))
        } else {
            ContentUnavailableView("Nothing to show", systemImage: "list.bullet",
                                   description: Text("Scan a location to see what it holds."))
        }
    }

    private struct Row: View {
        let node: FileNode
        let name: String
        let share: Double
        let color: Color
        let isHovered: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
                    Image(systemName: icon).foregroundStyle(.secondary).frame(width: 14)
                    Text(name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(node.kind == .unreadable ? "No access" : node.size.bytes).monospacedDigit().foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(color).frame(width: max(geo.size.width * share, share > 0 ? 2 : 0))
                        }
                    }
                    .frame(height: 4)
                    Text(share, format: .percent.precision(.fractionLength(1)))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.leading, 18)
            }
            .padding(.vertical, 2)
            .listRowBackground(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
        }

        private var icon: String {
            switch node.kind {
            case .folder: "folder"
            case .file: "doc"
            case .smallFiles: "square.stack"
            case .unreadable: "lock"
            }
        }
    }
}
