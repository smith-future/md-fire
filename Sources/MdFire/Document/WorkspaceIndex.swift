import Foundation
import Observation
import MarkdownCore

/// An async, cached, watcher-invalidated index of the workspace's markdown CONTENT — the single
/// source of truth feeding the sidebar checklist badges (F2 rollup), the ⌘P palette + full-text
/// search + backlinks (F4). `WorkspaceModel.buildTree` only lists files (no reads); this reads and
/// parses each file off the main thread so launch never blocks, then republishes on the main actor.
/// The FileWatcher re-indexes only the file that changed, never the whole tree.
@Observable
final class WorkspaceIndex {

    /// One file's distilled content: enough for rollups, search, link-following, and backlinks.
    struct Entry: Equatable {
        let url: URL
        let text: String
        let taskDone: Int
        let taskTotal: Int
        let outboundLinks: [String]   // raw destinations: ./rel.md, https://…, [[wiki]] targets
        let headings: [String]
    }

    private(set) var entries: [URL: Entry] = [:]
    private(set) var isIndexing = false
    /// Fired (on the main queue) when files are ADDED or REMOVED under the root, so the sidebar tree
    /// can rebuild. NOT fired for mere content edits — those only re-index in place.
    @ObservationIgnored var onStructureChange: (() -> Void)?

    @ObservationIgnored private var root: URL?
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var generation = 0
    private static let exts: Set<String> = ["md", "markdown", "mdown", "txt"]

    // MARK: - Lifecycle

    /// Point the index at a new workspace root: full async reindex + start watching the tree.
    func setRoot(_ url: URL?) {
        root = url
        watcher = nil
        guard let url else { entries = [:]; return }
        reindexAll(url)
        watcher = FileWatcher.tree(url) { [weak self] changed in
            self?.handleTreeChange(changed)
        }
    }

    /// Canonical dictionary key. FSEvents reports symlink-RESOLVED paths while the enumerator yields
    /// paths as-rooted, so both sides must normalize identically or edits duplicate and deletes ghost
    /// (e.g. a workspace under /tmp or /var, which are symlinks to /private on macOS).
    static func key(_ url: URL) -> URL { url.resolvingSymlinksInPath().standardizedFileURL }

    private func handleTreeChange(_ changed: [URL]) {
        var structureChanged = false
        for url in changed where Self.exts.contains(url.pathExtension.lowercased()) {
            let key = Self.key(url)
            if FileManager.default.fileExists(atPath: url.path) {
                if entries[key] == nil { structureChanged = true }   // a new file appeared
                reindexFile(url)
            } else {
                if entries[key] != nil { structureChanged = true }   // a file was removed
                entries[key] = nil
            }
        }
        if structureChanged { onStructureChange?() }
    }

    // MARK: - Indexing (off the main thread)

    private func reindexAll(_ root: URL) {
        generation += 1
        let gen = generation
        isIndexing = true
        Task.detached(priority: .utility) {
            let files = Self.enumerateMarkdown(root)
            var built: [URL: Entry] = [:]
            for file in files {
                if let entry = Self.makeEntry(file) { built[entry.url] = entry }
            }
            await MainActor.run { [weak self] in
                guard let self, gen == self.generation else { return }   // a newer reindex superseded us
                self.entries = built
                self.isIndexing = false
            }
        }
    }

    private func reindexFile(_ url: URL) {
        let key = Self.key(url)
        let gen = generation
        Task.detached(priority: .utility) {
            let entry = Self.makeEntry(url)
            await MainActor.run { [weak self] in
                // Drop a per-file reindex that belongs to a superseded workspace (setRoot bumped gen).
                guard let self, gen == self.generation else { return }
                self.entries[key] = entry
            }
        }
    }

    private static func enumerateMarkdown(_ root: URL) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        func walk(_ dir: URL) {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: []) else { return }
            for item in items {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDir {
                    if SpecialFiles.shouldSkipDirectory(item.lastPathComponent) { continue }
                    walk(item)
                } else if !item.lastPathComponent.hasPrefix("."), exts.contains(item.pathExtension.lowercased()) {
                    out.append(item)
                }
            }
        }
        walk(root)
        return out
    }

    private static func makeEntry(_ url: URL) -> Entry? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let (done, total, links, headings) = analyze(text)
        return Entry(url: key(url), text: text,
                     taskDone: done, taskTotal: total, outboundLinks: links, headings: headings)
    }

    /// Pull task counts, outbound link destinations, and headings out of a parse.
    static func analyze(_ text: String) -> (done: Int, total: Int, links: [String], headings: [String]) {
        let ns = text as NSString
        var done = 0, total = 0
        var links: [String] = []
        var headings: [String] = []
        for node in TreeSitterParser().parse(text) {
            switch node.role {
            case .taskItem(let checked):
                total += 1; if checked { done += 1 }
            case .link, .autolink, .image:
                if let dest = node.linkDestination, !dest.isEmpty { links.append(dest) }
            case .heading:
                if node.contentRange.location != NSNotFound,
                   NSMaxRange(node.contentRange) <= ns.length {
                    headings.append(ns.substring(with: node.contentRange))
                }
            default:
                break
            }
        }
        return (done, total, links, headings)
    }

    // MARK: - Queries (F2 / F4)

    /// Checklist completion for one file (nil if not indexed or it has no tasks).
    func progress(for url: URL) -> (done: Int, total: Int)? {
        guard let e = entries[Self.key(url)], e.taskTotal > 0 else { return nil }
        return (e.taskDone, e.taskTotal)
    }

    /// Checklist completion summed over every indexed file under `folder` (F2 folder rollup).
    func rollup(under folder: URL) -> (done: Int, total: Int)? {
        let prefix = Self.key(folder).path
        var done = 0, total = 0
        for e in entries.values where e.url.path == prefix || e.url.path.hasPrefix(prefix + "/") {
            done += e.taskDone; total += e.taskTotal
        }
        return total > 0 ? (done, total) : nil
    }

    /// All indexed markdown files (for the ⌘P fuzzy-open palette).
    func allFiles() -> [URL] { Array(entries.keys) }

    // MARK: - ⌘P fuzzy open + ⌘⇧F full-text search (F4)

    /// A full-text search hit: the file, the matched range, and a one-line snippet for the palette.
    struct SearchHit: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let range: NSRange
        let snippet: String
    }

    /// Files ranked by a fuzzy subsequence match of `query` against the filename (empty query =
    /// all files, name-sorted).
    func fuzzyFiles(_ query: String, limit: Int = 60) -> [URL] {
        let files = allFiles()
        let q = query.lowercased()
        guard !q.isEmpty else {
            return files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .prefix(limit).map { $0 }
        }
        return files.compactMap { url -> (URL, Int)? in
            Self.fuzzyScore(q, url.lastPathComponent.lowercased()).map { (url, $0) }
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit).map { $0.0 }
    }

    /// Subsequence score: every query char must appear in order; contiguous runs score higher.
    static func fuzzyScore(_ query: String, _ candidate: String) -> Int? {
        let q = Array(query), c = Array(candidate)
        var qi = 0, ci = 0, score = 0, streak = 0
        while qi < q.count, ci < c.count {
            if q[qi] == c[ci] { score += 1 + streak; streak += 1; qi += 1 }
            else { streak = 0 }
            ci += 1
        }
        return qi == q.count ? score : nil
    }

    /// Case-insensitive full-text search across every indexed file (a few hits per file, capped).
    func fullTextSearch(_ query: String, limit: Int = 80) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for entry in entries.values.sorted(by: { $0.url.path < $1.url.path }) {
            let ns = entry.text as NSString
            var from = 0, perFile = 0
            while perFile < 6, from < ns.length {
                let found = ns.range(of: q, options: .caseInsensitive,
                                     range: NSRange(location: from, length: ns.length - from))
                guard found.location != NSNotFound else { break }
                hits.append(SearchHit(url: entry.url, range: found, snippet: Self.lineSnippet(ns, found)))
                perFile += 1
                from = NSMaxRange(found)
                if hits.count >= limit { return hits }
            }
            if hits.count >= limit { break }
        }
        return hits
    }

    /// The trimmed line of text containing `range`, for the search-results list.
    private static func lineSnippet(_ ns: NSString, _ range: NSRange) -> String {
        let line = ns.lineRange(for: NSRange(location: range.location, length: 0))
        return ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Files whose content references `target`'s basename (F4 backlinks).
    func backlinks(to target: URL) -> [URL] {
        let base = target.deletingPathExtension().lastPathComponent
        let full = target.lastPathComponent
        let targetKey = Self.key(target)
        return entries.values.compactMap { entry -> URL? in
            guard entry.url != targetKey else { return nil }
            let hit = entry.outboundLinks.contains { dest in
                let last = (dest as NSString).lastPathComponent
                return dest == base || last == full || (last as NSString).deletingPathExtension == base
            }
            return hit ? entry.url : nil
        }
    }
}
