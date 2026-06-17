import SwiftUI

/// The workspace file tree. Selecting a file row opens it (RootView watches `selection`); folders
/// expand/collapse via disclosure. Empty state offers to open a folder.
struct FileTreeView: View {
    let workspace: WorkspaceModel
    @Binding var selection: URL?

    var body: some View {
        if workspace.root == nil {
            ContentUnavailableView {
                Label("No Folder Open", systemImage: "folder")
            } description: {
                Text("Open a folder to browse its Markdown files.")
            } actions: {
                Button("Open Folder…") { workspace.openFolder() }
            }
        } else {
            List(selection: $selection) {
                Section(workspace.root?.lastPathComponent.uppercased() ?? "FILES") {
                    OutlineGroup(workspace.tree, children: \.children) { node in
                        Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
                            .tag(node.url)
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }
}
