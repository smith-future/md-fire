import Foundation

/// Recognises the files an AI-coding workflow cares about (CLAUDE.md, ROADMAP.md, *-SPEC.md, and
/// anything under `.planning/`) so the cockpit can pin them atop the sidebar, plus the directory
/// allow/deny rules that let `.planning/` (a dotfolder) through while still pruning `.git`,
/// `node_modules`, build output, etc.
enum SpecialFiles {

    /// Exact filenames that are always special.
    static let specialNames: Set<String> = ["CLAUDE.md", "AGENTS.md", "ROADMAP.md"]

    /// True if `url` is a special plan/spec file worth pinning.
    static func isSpecial(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if specialNames.contains(name) { return true }
        if name.hasSuffix("-SPEC.md") || name.hasSuffix("-spec.md") { return true }
        return url.pathComponents.contains(".planning")
    }

    /// A short tag for the pinned row (e.g. "PLAN", "SPEC", "AGENT", "PLANNING").
    static func tag(for url: URL) -> String {
        let name = url.lastPathComponent
        if name == "ROADMAP.md" { return "PLAN" }
        if name == "CLAUDE.md" || name == "AGENTS.md" { return "AGENT" }
        if name.hasSuffix("-SPEC.md") || name.hasSuffix("-spec.md") { return "SPEC" }
        if url.pathComponents.contains(".planning") { return "PLANNING" }
        return "DOC"
    }

    /// Whether a directory named `name` should be skipped when scanning a workspace. `.planning` is
    /// explicitly allowed even though it's a dotfolder; every other dotfolder and known build/vendor
    /// folder is pruned.
    static func shouldSkipDirectory(_ name: String) -> Bool {
        if name == ".planning" { return false }
        if name.hasPrefix(".") { return true }
        return ["node_modules", "Pods", "DerivedData", "build", "dist", "vendor"].contains(name)
    }
}
