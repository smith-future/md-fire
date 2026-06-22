import AppKit
import Observation

/// A node in the workspace file tree (a folder or a markdown file).
struct FileNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]?

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// The open workspace: a root folder and its nested tree of markdown files. Drives the sidebar.
/// FSEvents watching + security-scoped bookmark persistence are layered on next.
@Observable
final class WorkspaceModel {
    var root: URL?
    var tree: [FileNode] = []
    /// Async content index (task rollups, full-text search, links/backlinks) kept in sync with `root`.
    let index = WorkspaceIndex()

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "txt"]
    private let defaultsKey = "md-fire.workspaceRoot"

    init() {
        // When an agent creates/deletes files under the workspace, rebuild the tree so they appear live.
        index.onStructureChange = { [weak self] in self?.refresh() }
        restore()
    }

    /// Re-open the last workspace on launch (sandbox is off, so a plain path suffices; a
    /// security-scoped bookmark would replace this if the app is ever sandboxed).
    private func restore() {
        guard let path = UserDefaults.standard.string(forKey: defaultsKey) else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }
        let url = URL(fileURLWithPath: path)
        root = url
        tree = Self.buildTree(at: url)
        index.setRoot(url)
    }

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setRoot(url)
    }

    func setRoot(_ url: URL) {
        root = url
        tree = Self.buildTree(at: url)
        index.setRoot(url)
        UserDefaults.standard.set(url.path, forKey: defaultsKey)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func refresh() {
        guard let root else { return }
        tree = Self.buildTree(at: root)
    }

    /// Special plan/spec files (CLAUDE.md, ROADMAP.md, *-SPEC.md, anything under .planning/) flattened
    /// from the tree, for the pinned sidebar section. Reads `tree` so it stays live.
    var specialFiles: [URL] {
        var out: [URL] = []
        func walk(_ nodes: [FileNode]) {
            for node in nodes {
                if let kids = node.children { walk(kids) }
                else if SpecialFiles.isSpecial(node.url) { out.append(node.url) }
            }
        }
        walk(tree)
        return out.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Recursive listing: markdown files, plus folders that (recursively) contain at least one.
    /// Dotfolders are pruned EXCEPT `.planning/` (so agent plans show); build/vendor dirs are pruned.
    static func buildTree(at url: URL) -> [FileNode] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [] }

        var nodes: [FileNode] = []
        for item in items {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                if SpecialFiles.shouldSkipDirectory(item.lastPathComponent) { continue }
                let children = buildTree(at: item)
                if !children.isEmpty {
                    nodes.append(FileNode(url: item, isDirectory: true, children: children))
                }
            } else if !item.lastPathComponent.hasPrefix("."),
                      markdownExtensions.contains(item.pathExtension.lowercased()) {
                nodes.append(FileNode(url: item, isDirectory: false, children: nil))
            }
        }

        return nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }   // folders first
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
