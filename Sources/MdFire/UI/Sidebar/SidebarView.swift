import SwiftUI
import MarkdownCore

/// A heading in the current document's outline.
struct OutlineItem: Identifiable, Hashable {
    let id = UUID()
    let level: Int
    let title: String
    let range: NSRange
}

/// The sidebar: the workspace file tree plus the current document's heading outline. Selecting a file
/// opens it (via `selection`); clicking an outline item jumps the editor to that heading.
struct SidebarView: View {
    let workspace: WorkspaceModel
    @Binding var selection: URL?
    let documentText: String
    let onOutlineSelect: (NSRange) -> Void

    private static let parser = TreeSitterParser()

    var body: some View {
        List(selection: $selection) {
            if let root = workspace.root {
                Section(root.lastPathComponent.uppercased()) {
                    OutlineGroup(workspace.tree, children: \.children) { node in
                        Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
                            .tag(node.url)
                    }
                }
            } else {
                Section {
                    Button {
                        workspace.openFolder()
                    } label: {
                        Label("Open Folder…", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.plain)
                }
            }

            let outline = Self.outline(from: documentText)
            if !outline.isEmpty {
                Section("OUTLINE") {
                    ForEach(outline) { item in
                        Button {
                            onOutlineSelect(item.range)
                        } label: {
                            Text(item.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .font(.system(size: 12, weight: item.level <= 2 ? .medium : .regular))
                                .foregroundStyle(item.level <= 2 ? .primary : .secondary)
                                .padding(.leading, CGFloat(max(0, item.level - 1)) * 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    static func outline(from text: String) -> [OutlineItem] {
        let ns = text as NSString
        return parser.parse(text).compactMap { node in
            guard case .heading(let level) = node.role else { return nil }
            let title = ns.substring(with: node.contentRange).trimmingCharacters(in: .whitespaces)
            return OutlineItem(level: level, title: title.isEmpty ? "—" : title, range: node.nodeRange)
        }
    }
}
