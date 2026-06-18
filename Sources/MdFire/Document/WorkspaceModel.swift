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

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "txt"]
    private let defaultsKey = "md-fire.workspaceRoot"

    init() { restore() }

    /// Re-open the last workspace on launch (sandbox is off, so a plain path suffices; a
    /// security-scoped bookmark would replace this if the app is ever sandboxed).
    private func restore() {
        guard let path = UserDefaults.standard.string(forKey: defaultsKey) else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }
        let url = URL(fileURLWithPath: path)
        root = url
        tree = Self.buildTree(at: url)
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
        UserDefaults.standard.set(url.path, forKey: defaultsKey)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func refresh() {
        guard let root else { return }
        tree = Self.buildTree(at: root)
    }

    /// Recursive listing: markdown files, plus folders that (recursively) contain at least one.
    static func buildTree(at url: URL) -> [FileNode] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var nodes: [FileNode] = []
        for item in items {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                let children = buildTree(at: item)
                if !children.isEmpty {
                    nodes.append(FileNode(url: item, isDirectory: true, children: children))
                }
            } else if markdownExtensions.contains(item.pathExtension.lowercased()) {
                nodes.append(FileNode(url: item, isDirectory: false, children: nil))
            }
        }

        return nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }   // folders first
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
