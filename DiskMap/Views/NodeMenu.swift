import SwiftUI

/// The right-click menu shared by treemap boxes and inspector rows.
struct NodeMenu: View {
    @Environment(AppModel.self) private var model
    let node: FileNode

    var body: some View {
        let removable = model.removalRefusal(for: node) == nil

        if node.isFolder && !node.children.isEmpty {
            Button("Open", systemImage: "arrow.down.right.and.arrow.up.left") { model.open(node) }
            Divider()
        }
        Button("Show in Finder", systemImage: "folder") { model.revealInFinder(node) }
            .disabled(!node.isRealItem)
        Button("Quick Look", systemImage: "eye") { model.quickLook(node) }
            .disabled(!node.isRealItem)
        Button("Copy Path", systemImage: "doc.on.doc") { model.copyPath(node) }
        Divider()
        Button("Move to Trash…", systemImage: "trash") { model.requestRemoval(of: node, permanently: false) }
            .disabled(!removable)
        Button("Delete Permanently…", systemImage: "xmark.bin", role: .destructive) {
            model.requestRemoval(of: node, permanently: true)
        }
        .disabled(!removable)
    }
}
