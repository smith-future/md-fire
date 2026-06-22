import Foundation

/// Resolves a markdown link destination to a file on disk (F4 click-to-follow + ⌘P targets):
/// relative `./ARCHITECTURE.md` paths against the current document, and bare `[[wiki]]` names
/// against the workspace index — preferring the **nearest** path when a basename is ambiguous,
/// which matches how people mentally link within a plan tree.
enum LinkResolver {
    static func resolve(_ destination: String, from current: URL?, workspace: WorkspaceModel) -> URL? {
        let dest = destination.trimmingCharacters(in: .whitespaces)
        guard !dest.isEmpty, !dest.hasPrefix("#") else { return nil }
        let pathPart = String(dest.split(separator: "#", maxSplits: 1).first ?? Substring(dest))
        let fm = FileManager.default

        // 1) A relative/explicit filesystem path: try against the current file's folder, then root.
        if pathPart.contains("/") || pathPart.contains(".") {
            var bases: [URL] = []
            if let dir = current?.deletingLastPathComponent() { bases.append(dir) }
            if let root = workspace.root { bases.append(root) }
            for base in bases {
                let direct = base.appendingPathComponent(pathPart).standardizedFileURL
                if fm.fileExists(atPath: direct.path) { return direct }
                let withMD = direct.appendingPathExtension("md")
                if fm.fileExists(atPath: withMD.path) { return withMD }
            }
        }

        // 2) A bare name / wiki target: match basename in the index, nearest path wins.
        let wantedBase = ((pathPart as NSString).lastPathComponent as NSString)
            .deletingPathExtension.lowercased()
        let matches = workspace.index.allFiles().filter {
            $0.deletingPathExtension().lastPathComponent.lowercased() == wantedBase
        }
        guard !matches.isEmpty else { return nil }
        if let current { return matches.max { sharedDepth($0, current) < sharedDepth($1, current) } }
        return matches.first
    }

    /// Count of leading path components the two URLs' directories share — a "closeness" score.
    private static func sharedDepth(_ url: URL, _ current: URL) -> Int {
        let a = url.deletingLastPathComponent().pathComponents
        let b = current.deletingLastPathComponent().pathComponents
        var n = 0
        while n < min(a.count, b.count), a[n] == b[n] { n += 1 }
        return n
    }
}
