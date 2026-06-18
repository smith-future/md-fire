import SwiftUI
import MarkdownCore

/// The app shell: a sidebar (workspace file tree) + the editor in a fixed, centered reading column,
/// with a slim bottom status bar (mode, measure, focus, typewriter, theme, word count).
struct RootView: View {
    let document: MarkdownDocument
    let workspace: WorkspaceModel
    let editor: EditorController

    @State private var mode: RenderMode = .liveWYSIWYG
    @State private var measure = 72
    @State private var isDark = false
    @State private var focus: FocusScope = .off
    @State private var typewriter = false
    @State private var posHighlight = false
    @State private var bionic = false
    @State private var selectedFile: URL?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isDropTargeted = false
    @State private var telegramCopied = false

    private var theme: Theme { isDark ? .dark : .light }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                workspace: workspace,
                selection: $selectedFile,
                documentText: document.text,
                onOutlineSelect: { editor.reveal($0) }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
        } detail: {
            editorArea
        }
        .preferredColorScheme(isDark ? .dark : .light)
        .navigationTitle(document.displayName)
        .onChange(of: selectedFile) { _, newValue in
            if let url = newValue, !isDirectory(url) { document.openFile(at: url) }
        }
        // Drag a file/folder from Finder anywhere onto the window to open it.
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            return handleDrop(url)
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(theme.palette.accent), lineWidth: 3)
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
    }

    private func handleDrop(_ url: URL) -> Bool {
        if isDirectory(url) {
            workspace.setRoot(url)
            return true
        }
        guard WorkspaceModel.markdownExtensions.contains(url.pathExtension.lowercased()) else {
            return false
        }
        document.openFile(at: url)
        if workspace.root == nil {
            // Adopt the dropped file's folder as the workspace so the sidebar isn't empty.
            workspace.setRoot(url.deletingLastPathComponent())
        }
        selectedFile = url
        return true
    }

    private var editorArea: some View {
        VStack(spacing: 0) {
            TextKitEditor(
                text: document.text,
                mode: mode,
                theme: theme,
                focusScope: focus,
                typewriter: typewriter,
                posHighlight: posHighlight,
                bionic: bionic,
                controller: editor,
                onChange: { document.userEdited($0) }
            )
            .frame(maxWidth: theme.columnWidth(chars: measure))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            statusBar
        }
        .background(Color(theme.palette.bg))
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Button { toggleSidebar() } label: { Image(systemName: "sidebar.left") }
                .buttonStyle(.borderless)
                .help("Toggle sidebar")

            Picker("", selection: $mode) {
                ForEach(RenderMode.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 140)

            Picker("", selection: $measure) {
                ForEach([64, 72, 80], id: \.self) { Text("\($0)").tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 120)

            Picker("Focus", selection: $focus) {
                ForEach(FocusScope.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Menu {
                Toggle("Typewriter", isOn: $typewriter)
                Toggle("Bionic reading", isOn: $bionic)
                Toggle("Parts of speech", isOn: $posHighlight)
                Divider()
                Toggle("Dark theme", isOn: $isDark)
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("View options")

            Spacer()

            Button {
                TelegramFormatter.copyToPasteboard(from: document.text)
                telegramCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { telegramCopied = false }
            } label: {
                Label(telegramCopied ? "Copied!" : "Telegram",
                      systemImage: telegramCopied ? "checkmark.circle.fill" : "paperplane.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .fixedSize()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(telegramCopied ? Color.green : Color(theme.palette.accent))
            .help("Copy the document formatted for Telegram, then paste it into a chat")

            Text("\(wordCount) words")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private var wordCount: Int {
        document.text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    private func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.18)) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }
}
