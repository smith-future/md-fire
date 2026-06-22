import SwiftUI
import Observation

/// Transient controller for the ⌘P / ⌘⇧F palette. Owned by the app and toggled from the menu
/// commands (keyboard focus on a bare overlay is flaky, so the trigger lives in a CommandMenu).
@Observable
final class PaletteModel {
    enum Mode { case files, search }
    var mode: Mode?
    func openFiles() { mode = .files }
    func openSearch() { mode = .search }
    func dismiss() { mode = nil }
}

/// The Spotlight-style overlay: a query field over the workspace index. `.files` fuzzy-matches
/// filenames (⌘P); `.search` runs a full-text search (⌘⇧F). Enter opens the selection (and, for a
/// search hit, reveals the match); arrows move; Esc dismisses.
struct CommandPaletteView: View {
    let mode: PaletteModel.Mode
    let workspace: WorkspaceModel
    let onPick: (URL, NSRange?) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private struct Item: Identifiable {
        let id = UUID()
        let url: URL
        let title: String
        let subtitle: String
        let icon: String
        let range: NSRange?
    }

    private var items: [Item] {
        switch mode {
        case .files:
            return workspace.index.fuzzyFiles(query).map {
                Item(url: $0, title: $0.lastPathComponent, subtitle: relativePath($0),
                     icon: "doc.text", range: nil)
            }
        case .search:
            return workspace.index.fullTextSearch(query).map {
                Item(url: $0.url, title: $0.url.lastPathComponent, subtitle: $0.snippet,
                     icon: "text.alignleft", range: $0.range)
            }
        }
    }

    var body: some View {
        let results = items
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: mode == .files ? "doc.text.magnifyingglass" : "text.magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(mode == .files ? "Go to file…" : "Search the workspace…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($focused)
                    .onSubmit { pick(results, selection) }
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results.indices, id: \.self) { idx in
                            row(results[idx], idx: idx, total: results.count)
                                .id(idx)
                        }
                        if results.isEmpty {
                            Text(query.isEmpty ? "Type to search…" : "No matches")
                                .foregroundStyle(.secondary)
                                .padding(14)
                        }
                    }
                }
                .onChange(of: selection) { _, new in proxy.scrollTo(new) }
            }
        }
        .frame(width: 580, height: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in selection = 0 }
        .onKeyPress(.downArrow) { move(1, total: results.count); return .handled }
        .onKeyPress(.upArrow) { move(-1, total: results.count); return .handled }
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .onExitCommand { onDismiss() }   // reliable Escape even when the field editor swallows the key press
    }

    private func row(_ item: Item, idx: Int, total: Int) -> some View {
        Button { onPick(item.url, item.range); onDismiss() } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon).foregroundStyle(.secondary).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(idx == selection ? Color.accentColor.opacity(0.22) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { selection = idx } }
    }

    private func move(_ delta: Int, total: Int) {
        guard total > 0 else { return }
        selection = min(max(0, selection + delta), total - 1)
    }

    private func pick(_ results: [Item], _ index: Int) {
        guard index >= 0, index < results.count else { return }
        let item = results[index]
        onPick(item.url, item.range)
        onDismiss()
    }

    private func relativePath(_ url: URL) -> String {
        guard let root = workspace.root else { return url.deletingLastPathComponent().lastPathComponent }
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path.hasPrefix(rootPath) ? String(url.path.dropFirst(rootPath.count)) : url.lastPathComponent
    }
}
