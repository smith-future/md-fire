import SwiftUI
import MarkdownCore

/// A heading in the current document's outline.
struct OutlineItem: Identifiable, Hashable {
    let level: Int
    let title: String
    let range: NSRange
    /// Stable identity (content + position) so the List diffs rows instead of tearing them all down
    /// on every keystroke — a fresh `UUID()` per parse made ForEach rebuild the whole outline.
    var id: String { "\(level):\(range.location):\(title)" }
}

/// The sidebar: the workspace file tree plus the current document's heading outline. Selecting a file
/// opens it (via `selection`); clicking an outline item jumps the editor to that heading.
struct SidebarView: View {
    let workspace: WorkspaceModel
    @Binding var selection: URL?
    let outline: [OutlineItem]
    var documentURL: URL? = nil
    var pinSpecialFiles: Bool = true
    let onOutlineSelect: (OutlineItem) -> Void
    var onNewFile: () -> Void = {}

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
        .safeAreaInset(edge: .bottom, spacing: 0) { newFileBar }
    }

    /// A slim footer toolbar (à la Finder / Mail) pinned under the file list, with a single "New file"
    /// action. Only shown once a workspace folder is open. No hover @State — mutating state from an
    /// `.onHover` that can fire during a split-view divider double-click's nested event/layout flush
    /// re-enters AppKit's constraint cycle and crashes; a static pill reads as a button without it.
    @ViewBuilder private var newFileBar: some View {
        if workspace.root != nil {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 0) {
                    Button(action: onNewFile) {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.pencil").font(.system(size: 12))
                            Text("New file").font(.system(size: 12)).lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("New file in this folder (⇧⌘N)")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .background(.bar)
        }
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
