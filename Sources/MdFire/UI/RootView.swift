import SwiftUI
import MarkdownCore

/// The app shell: a sidebar (workspace file tree) + the editor in a fixed, centered reading column,
/// with a slim bottom status bar (mode, measure, focus, typewriter, theme, word count).
struct RootView: View {
    let document: MarkdownDocument
    let splitDocument: MarkdownDocument
    let workspace: WorkspaceModel
    let editor: EditorController
    let splitEditor: EditorController
    @Bindable var settings: AppSettings
    let palette: PaletteModel
    let activePane: ActivePane

    @State private var mode: RenderMode = .syntaxVisible   // raw markdown editor; Preview renders it
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
    @State private var statusIdle = false
    @State private var idleWork: DispatchWorkItem?
    @State private var reloadDismissWork: DispatchWorkItem?
    @State private var previewController = PreviewController()

    private var theme: Theme { isDark ? .dark : .light }

    /// The status-bar view selector: edit the raw markdown (Source) or read it rendered (Preview).
    private enum ViewMode: Hashable { case source, preview }
    private var viewMode: Binding<ViewMode> {
        Binding(
            get: { settings.previewVisible ? .preview : .source },
            set: { settings.previewVisible = ($0 == .preview) }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                workspace: workspace,
                selection: $selectedFile,
                documentText: document.text,
                documentURL: document.fileURL,
                pinSpecialFiles: settings.pinSpecialFiles,
                onOutlineSelect: { item in
                    // Preview is full-screen (no editor): scroll the rendered pane; else jump the editor.
                    if settings.previewVisible { previewController.scrollToHeading?(item.title) }
                    else { editor.reveal(item.range) }
                }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 360)
        } detail: {
            editorArea
        }
        .preferredColorScheme(isDark ? .dark : .light)
        .navigationTitle(document.displayName)
        .onChange(of: selectedFile) { _, newValue in
            guard let url = newValue, !isDirectory(url) else { return }
            document.openFile(at: url)
            // If the open was declined (unsaved-changes cancel), resync the highlight to what's open.
            if document.fileURL != url { selectedFile = document.fileURL }
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
        .overlay { paletteOverlay }
    }

    /// The ⌘P / ⌘⇧F command palette, dimming the window behind it; click-out or Esc dismisses.
    @ViewBuilder private var paletteOverlay: some View {
        if let mode = palette.mode {
            ZStack(alignment: .top) {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture { palette.dismiss() }
                CommandPaletteView(
                    mode: mode,
                    workspace: workspace,
                    onPick: { url, range in openFromPalette(url, range) },
                    onDismiss: { palette.dismiss() }
                )
                .padding(.top, 80)
            }
            .transition(.opacity)
        }
    }

    /// Open a palette result; for a search hit, reveal the matched range once the editor has the text.
    /// Drive ONLY `selectedFile` — its `.onChange` performs the open, so we never prompt to discard twice.
    private func openFromPalette(_ url: URL, _ range: NSRange?) {
        if selectedFile == url { document.openFile(at: url) }   // already selected → onChange won't fire
        else { selectedFile = url }
        if let range {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { editor.reveal(range) }
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
            if settings.previewVisible {
                // Full-area rendered reader (tables / Mermaid / code / math). Switch to Source to edit.
                PreviewWebView(markdown: document.text, title: document.displayName, dark: isDark,
                               columnChars: measure,
                               controller: previewController,
                               onToggleTask: { document.toggleTask($0) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if settings.splitView {
                HSplitView {
                    pane(document: document, editor: editor, isPrimary: true)
                    pane(document: splitDocument, editor: splitEditor, isPrimary: false)
                }
            } else {
                pane(document: document, editor: editor, isPrimary: true)
            }

            statusBar
        }
        .background(Color(theme.palette.bg))
        .background(FloatingWindowAccessor(floating: settings.alwaysOnTop))
        .safeAreaInset(edge: .top, spacing: 0) { reloadBanner }
        // Status bar fades out after a few seconds of inactivity; any typing or mouse movement
        // over the editor (status bar included) wakes it back up.
        .onChange(of: document.text) { _, _ in bumpStatusActivity() }
        .onContinuousHover { phase in
            if case .active = phase { bumpStatusActivity() }
        }
        .onAppear { bumpStatusActivity() }
        .onChange(of: document.externalChange) { _, change in
            if case .reloaded = change { scheduleReloadBannerDismiss() }
        }
    }

    /// Slim top banner: a transient "reloaded" toast, or a persistent conflict prompt with actions.
    @ViewBuilder private var reloadBanner: some View {
        switch document.externalChange {
        case .reloaded(let changes):
            banner(background: theme.palette.accent) {
                Label(changes > 0 ? "Reloaded — \(changes) section\(changes == 1 ? "" : "s") changed"
                                  : "Reloaded from disk",
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .transition(.move(edge: .top).combined(with: .opacity))

        case .conflict:
            banner(background: NSColor.systemOrange) {
                Label("This file changed on disk", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Button("Reload") { document.resolveConflictTakeDisk() }
                    .controlSize(.small)
                Button("Keep Mine") { document.resolveConflictKeepMine() }
                    .controlSize(.small)
            }
            .layoutPriority(-1)

        case .none:
            EmptyView()
        }
    }

    private func banner<Content: View>(background: NSColor, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10) { content() }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(background))
    }

    private func scheduleReloadBannerDismiss() {
        reloadDismissWork?.cancel()
        let work = DispatchWorkItem {
            withAnimation(settings.statusFadeAnimation) { document.dismissReloadBanner() }
        }
        reloadDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }

    /// One editor pane. In split view both panes fill their half and show a slim header (filename +
    /// Open); single view keeps the centered reading column and no header.
    private func pane(document doc: MarkdownDocument, editor ed: EditorController, isPrimary: Bool) -> some View {
        // The split header belongs only to the two-document split layout, not the editor+preview layout.
        let showsHeader = settings.splitView && !settings.previewVisible
        return VStack(spacing: 0) {
            if showsHeader {
                HStack(spacing: 8) {
                    Image(systemName: isPrimary ? "doc.text.fill" : "doc.text")
                        .foregroundStyle(.secondary).font(.system(size: 11))
                    Text(doc.displayName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 4)
                    Button { doc.open() } label: { Image(systemName: "folder").font(.system(size: 11)) }
                        .buttonStyle(.borderless).help("Open a file in this pane")
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(.bar)
                Divider()
            }

            TextKitEditor(
                text: doc.text,
                mode: mode,
                theme: theme,
                focusScope: focus,
                typewriter: typewriter,
                posHighlight: posHighlight,
                bionic: bionic,
                reduceMotion: settings.reduceMotion,
                controller: ed,
                onChange: { doc.userEdited($0) },
                onCheckboxToggle: { doc.saveIfBacked() },
                onFollowLink: { followLinkIn(doc, ed, $0) },
                onActivated: { activePane.editor = ed; activePane.document = doc },
                changedRanges: doc.changedRanges,
                reloadGeneration: doc.reloadGeneration
            )
            .frame(maxWidth: settings.splitView ? .infinity : theme.columnWidth(chars: measure))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Follow an internal link within a specific pane's document. The primary pane routes through
    /// `selectedFile` (single discard prompt via its onChange); the split pane opens directly.
    private func followLinkIn(_ doc: MarkdownDocument, _ ed: EditorController, _ destination: String) {
        guard let url = LinkResolver.resolve(destination, from: doc.fileURL, workspace: workspace) else { return }
        if doc === document, selectedFile != url {
            selectedFile = url
        } else {
            doc.openFile(at: url)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Button { toggleSidebar() } label: { Image(systemName: "sidebar.left") }
                .buttonStyle(.borderless)
                .help("Toggle sidebar")

            Picker("", selection: viewMode) {
                Text("Source").tag(ViewMode.source)
                Text("Preview").tag(ViewMode.preview)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 150)
            .help("Source = edit raw markdown · Preview = rendered (tables, Mermaid, code, math)")

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
                Section("Cockpit") {
                    Toggle("Preview pane", isOn: $settings.previewVisible)
                    Toggle("Auto-reload on disk change", isOn: $settings.autoReload)
                    Toggle("Highlight changes", isOn: $settings.showChanges)
                    Toggle("Pin special files", isOn: $settings.pinSpecialFiles)
                    Toggle("Float above other apps", isOn: $settings.alwaysOnTop)
                    Toggle("Split view", isOn: $settings.splitView)
                }
                Section("Writing") {
                    Toggle("Typewriter", isOn: $typewriter)
                    Toggle("Bionic reading", isOn: $bionic)
                    Toggle("Parts of speech", isOn: $posHighlight)
                }
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

            // Reading stats. NOT .fixedSize() — that forces the whole HStack wider than a narrow
            // window's first layout pass and re-triggers the AutoLayout overflow crash (CLAUDE.md).
            // Low layout priority + tail truncation: it yields space before the pickers/buttons,
            // yet shows in full at any normal window size.
            if let progress = document.taskProgress {
                Label("\(progress.done)/\(progress.total)",
                      systemImage: progress.done == progress.total ? "checkmark.circle.fill" : "checklist")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(progress.done == progress.total ? Color.green : .secondary)
                    .lineLimit(1)
                    .layoutPriority(-1)
                    .help("\(progress.done) of \(progress.total) checklist items done")
            }

            Text("\(wordCount) words · \(readingMinutes) min read")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
        .opacity(statusIdle ? 0.18 : 1)
    }

    private var wordCount: Int {
        document.text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }

    /// Estimated reading time in whole minutes (≥1), reusing `wordCount` — no extra text scan.
    private var readingMinutes: Int {
        max(1, Int((Double(wordCount) / Double(settings.readingWPM)).rounded()))
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    private func toggleSidebar() {
        withAnimation(settings.reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
    }

    /// Mark the user as active: restore the status bar now and re-arm the fade timer. Every call
    /// cancels the pending fade first, so overlapping timers never flicker the bar.
    private func bumpStatusActivity() {
        if statusIdle {
            withAnimation(settings.statusFadeAnimation) { statusIdle = false }
        }
        idleWork?.cancel()
        let work = DispatchWorkItem {
            withAnimation(settings.statusFadeAnimation) { statusIdle = true }
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}
