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
    var documentURL: URL? = nil
    var pinSpecialFiles: Bool = true
    let onOutlineSelect: (OutlineItem) -> Void

    private static let parser = TreeSitterParser()

    var body: some View {
        List(selection: $selection) {
            if pinSpecialFiles {
                let pinned = workspace.specialFiles
                if !pinned.isEmpty {
                    Section("PINNED") {
                        // Buttons (not `.tag`) so the same file pinned AND present in the tree doesn't
                        // create a duplicate selection identifier in the List. Setting `selection`
                        // drives the same open + highlights its row in the tree below.
                        ForEach(pinned, id: \.self) { url in
                            Button { selection = url } label: {
                                HStack(spacing: 6) {
                                    Label(url.lastPathComponent, systemImage: "pin.fill")
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 2)
                                    Text(SpecialFiles.tag(for: url))
                                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(.quaternary, in: Capsule())
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets())
                        }
                    }
                }
            }

            if let root = workspace.root {
                Section(root.lastPathComponent.uppercased()) {
                    OutlineGroup(workspace.tree, children: \.children) { node in
                        HStack(spacing: 6) {
                            Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 2)
                            if let badge = checklistBadge(for: node) {
                                Text(badge.text)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(badge.complete ? Color.green : .secondary)
                                    .help("\(badge.text) checklist items done")
                            }
                        }
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

            if let documentURL {
                let backlinks = workspace.index.backlinks(to: documentURL)
                if !backlinks.isEmpty {
                    Section("BACKLINKS") {
                        ForEach(backlinks, id: \.self) { url in
                            Button { selection = url } label: {
                                Label(url.lastPathComponent, systemImage: "arrow.uturn.left")
                                    .lineLimit(1).truncationMode(.middle)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets())
                        }
                    }
                }
            }

            let outline = Self.outline(from: documentText)
            if !outline.isEmpty {
                Section("OUTLINE") {
                    ForEach(outline) { item in
                        Button {
                            onOutlineSelect(item)
                        } label: {
                            Text(item.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .font(.system(size: 12, weight: item.level <= 2 ? .medium : .regular))
                                .foregroundStyle(item.level <= 2 ? .primary : .secondary)
                                .padding(.leading, 10 + CGFloat(max(0, item.level - 1)) * 12)
                                .padding(.trailing, 10)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())   // whole row/block is the hit target
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets())
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// Checklist badge for a sidebar node: a file's own progress, or a folder's recursive rollup.
    private func checklistBadge(for node: FileNode) -> (text: String, complete: Bool)? {
        let counts = node.isDirectory
            ? workspace.index.rollup(under: node.url)
            : workspace.index.progress(for: node.url)
        guard let (done, total) = counts else { return nil }
        return ("\(done)/\(total)", done == total)
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
