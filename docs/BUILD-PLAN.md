# md-fire — Build Plan (empty repo → working v1)

An ordered, phased plan. The **riskiest part — the dual-mode live-render engine — is proven first** with a thin vertical slice, before any sidebar/export/Telegram work. Each phase states a **goal**, the **files** it touches/creates, and a **concrete verification** step.

> Conventions: macOS deployment target **14.0** (STTextView / TextKit 2 maturity). Xcode **26+**, Swift **5.9+**. Pin every dependency to an exact version/commit. Commit at each phase boundary on a feature branch.

---

## Phase 0 — Project scaffold

**Goal:** a runnable empty macOS `.app` with dependencies wired and the docs in place.

**Decision: Xcode `.app` project, not a SwiftPM executable.** A SwiftUI macOS app needs an `.app` bundle, `Info.plist`, entitlements (outgoing network for Telegram, security-scoped bookmarks), bundled font/theme/grammar resources, and code signing — all of which the Xcode app target manages cleanly. SwiftPM is used only to consume the remote dependencies (added via Xcode's "Add Package Dependencies").

**Exactly how to create it:**
1. In Xcode: **File → New → Project → macOS → App**. Product name `md-fire`, interface **SwiftUI**, language **Swift**, **no** Core Data, **no** tests-from-template (we add our own). Save into the existing repo root `/Users/smitty/Projects/personal-projects/md-fire/`.
2. Set deployment target to **macOS 14.0**.
3. **File → Add Package Dependencies…** and add, pinning exact versions:
   - `https://github.com/krzyzanowskim/STTextView` → `2.3.x`
   - `https://github.com/ChimeHQ/SwiftTreeSitter`
   - `https://github.com/ChimeHQ/Neon`
   - `https://github.com/swiftlang/swift-markdown`
   - `https://github.com/raspu/Highlightr` (or Splash)
   - tree-sitter-markdown + tree-sitter-markdown-inline grammar packages (or vendor compiled grammars under `Resources/Grammars/`).
4. Create the source folder structure from `ARCHITECTURE.md §2` under `Sources/MdFire/` (groups in Xcode mapped to folders).
5. In **Signing & Capabilities**: add **App Sandbox = off for now** (direct build; keeps Pandoc/Process open later) OR sandbox on with **Outgoing Connections (Client)** + **User Selected File (Read/Write)** — pick sandbox-off for v1 per ARCHITECTURE §8. Add the **com.apple.security.network.client** entitlement regardless (Telegram).
6. Move existing `docs/*.md` into the project navigator as a reference group (already on disk).

**Files created:** `md-fire.xcodeproj`, `Sources/MdFire/App/MdFireApp.swift` (template), `Info.plist`, `md-fire.entitlements`, empty domain folders.

**Verification:** `xcodebuild -project md-fire.xcodeproj -scheme md-fire build` succeeds; launching shows an empty window. `swift package resolve` (or Xcode's package graph) lists all pinned deps.

---

## Phase 1 — Range mapping + parser spike (engine foundation)

**Goal:** prove tree-sitter incremental parsing with correct **UTF-8 byte ↔ UTF-16 NSRange** mapping, emitting `SyntaxNode`s with content vs marker ranges. No UI yet.

**Files:** `Parser/SyntaxNode.swift`, `Parser/TreeSitterParser.swift`, `Engine/TextKitEngine/RangeMapping.swift`, `Parser/CmarkExportParser.swift` (oracle), `Tests/MdFireTests/RangeMappingTests.swift`, `ParserTests.swift`.

**Verification:** unit tests pass:
- Round-trip byte↔UTF-16 ranges for ASCII, accented, CJK, and emoji strings (no off-by-one).
- For `# Heading` and `**bold** _em_ `` `code` ``, the parser yields nodes whose `markerRanges` cover exactly the `#`, `**`, `_`, `` ` `` runs and `contentRange` covers exactly the rendered text — asserted against the cmark-gfm oracle for block structure.
- `Tree.edit()` + reparse after a single-char insert touches only the changed subtree (assert reparse time and changed-range scope).

---

## Phase 2 — THIN VERTICAL SLICE: dual-mode engine (highest risk, proven now)

**Goal:** a real `NSTextView` (STTextView, TextKit 2) wrapped in `NSViewRepresentable` that renders a hardcoded sample doc in **both** modes via one pipeline, switchable at runtime. This is the make-or-break phase.

**Sub-steps (in order):**
1. `Engine/MarkdownRenderingEngine.swift` protocol; `Engine/TextKitEngine/TextKitEngine.swift` hosting STTextView in **TextKit 2 mode** (assert it never touches `.layoutManager`).
2. `StylePolicy.swift` (`LiveWYSIWYGPolicy`, `SyntaxVisiblePolicy`) + `Styler.swift` applying content/marker attributes from Phase-1 nodes.
3. **iA / syntax-visible mode first** (lowest risk): markers dimmed, headings colored, code mono. Validates parser→mapping→attribute application end to end.
4. **WYSIWYG hiding — Stage 1**: collapse marker ranges + `AtomicRanges.swift` selection snapping (so caret can't land in hidden gaps).
5. **WYSIWYG hiding — Stage 2**: `HiddenMarkupFragment.swift` (custom `NSTextLayoutFragment` via `NSTextLayoutManagerDelegate`) that omits hidden glyphs and reports collapsed bounds.
6. `CaretReveal.swift`: on selection change, reveal the caret's enclosing block's markers; restore on exit. Guard against mouse-drag rebuilds.
7. Incremental restyle on edit via `NSTextStorageDelegate.didProcessEditing` + `Debouncer.swift` (~20 ms), scoped to the edited block.

**Files:** all of `Engine/TextKitEngine/*`, `Support/Debouncer.swift`, a temporary `DevHarnessView.swift` hosting the engine with a mode toggle button.

**Verification (the critical gate — maps to AC1.1–AC1.7):**
- Toggle button flips modes; the document String is byte-identical before/after (hash assertion in the harness).
- WYSIWYG: typing `**bold**` hides the `**` on close; arrowing into the word reveals `**`; arrowing out re-hides.
- Left/Right and Backspace treat hidden marker runs atomically (manual + an automated selection-movement test).
- Syntax-visible: same doc shows all dimmed markers; ordinary caret movement.
- No perceptible lag editing a pasted 5,000-line file (restyle scoped + debounced).
- **Decision checkpoint:** if Stage-2 hiding/atomicity proves intractable within the time box, activate the documented `WebViewEngine` fallback behind `MarkdownRenderingEngine` and proceed — the rest of the app is engine-agnostic.

---

## Phase 3 — App shell, document model, theme

**Goal:** real app structure: open/save a single file, the engine embedded in `RootView`, light/dark theme applied, fixed measure, fonts.

**Files:** `App/MdFireApp.swift`, `App/AppCommands.swift`, `App/AppEnvironment.swift`, `Document/MarkdownDocument.swift`, `Document/DocumentStore.swift`, `UI/RootView.swift`, `UI/EditorCanvas.swift`, `Theme/Theme.swift`, `Theme/ThemePalette.swift` (exact hexes from UI-DESIGN), `Theme/Typography.swift`, `Support/Settings.swift`, `Resources/Fonts/*`.

**Verification:**
- Open a `.md` via `⌘O`, edit, save (`⌘S`) — disk content matches, valid Markdown.
- Light/Dark toggle recolors background/body/selection/accent to the exact UI-DESIGN hexes; backgrounds are never `#FFF`/`#000`.
- Measure 64/72/80 segmented control resizes and re-centers the column; survives window resize and font change; min gutter holds on a narrow window.
- Editor uses the bundled writing font at the default size/line-height; caret/selection use the accent.

---

## Phase 4 — Focus Mode + Typewriter Mode

**Goal:** the signature writing aids, working in **both** editing models, via temp attributes + scroll control.

**Files:** `Overlays/FocusModeController.swift`, `Overlays/TypewriterController.swift`, `Support/Accessibility.swift`, Focus dropdown in `AppCommands.swift`.

**Verification (maps to AC3.1–AC3.7):**
- Focus dims all but the active scope; Sentence vs Paragraph scopes behave per `NLTokenizer`/`paragraphRange`; re-computes as caret moves.
- Dim/brighten eases ~150–200 ms; instant under Reduce Motion.
- Typewriter centers the caret line on typing and arrow movement; top/bottom padding lets first/last lines center; **no re-center during mouse-drag selection**.
- Document bytes unchanged throughout (hash assertion).

---

## Phase 5 — Sidebar: file tree + outline + workspace

**Goal:** open a folder as a workspace; nested file tree; live outline; persistence; swipe toggle.

**Files:** `Document/WorkspaceModel.swift` (FSEvents/`NSFilePresenter` + security-scoped bookmarks), `UI/Sidebar/FileTreeView.swift`, `UI/Sidebar/OutlineView.swift`, `UI/Sidebar/SidebarSwipe.swift`, `RootView.swift` (`NavigationSplitView`).

**Verification (maps to AC2.1–AC2.6):**
- "Open Folder…" populates a nested tree; clicking a file opens it; active file marked.
- Workspace re-opens on next launch with no permission prompt (bookmark).
- Finder add/remove/rename reflects in the sidebar within ~1 s.
- Outline lists H1–H6 (from the same parse), click scrolls, updates live.
- Sidebar toggles via menu, shortcut, and two-finger swipe.

---

## Phase 6 — Syntax Highlight (parts of speech)

**Goal:** editor-only grammatical coloring, per-POS toggle, debounced, scoped.

**Files:** `Overlays/SyntaxHighlightController.swift`, `Overlays/TaskFadeController.swift`, settings toggles in `UI/Settings/SettingsView.swift`.

**Verification (maps to AC4.5–AC4.6):**
- Toggling Syntax Highlight colors nouns red / verbs blue / adjectives brown / adverbs purple / conjunctions green via `NLTagger(.lexicalClass)`.
- Each POS toggles independently.
- Re-tag debounced ~200–300 ms, restricted to visible/edited paragraph; no lag on a long doc.
- Coloring never appears in the saved file (hash) nor in export (verified in Phase 7).
- Completed `- [x]` tasks fade/strikethrough via temp attrs.

---

## Phase 7 — Export: HTML + PDF

**Goal:** one themed-HTML renderer feeding standalone HTML export and paginated PDF export.

**Files:** `Export/HTMLRenderer.swift` (swift-markdown or Down → themed standalone HTML, inlined CSS + highlight.js), `Theme/ThemeCSS.swift`, `Export/HTMLExporter.swift`, `Export/PDFExporter.swift` (offscreen `WKWebView` → on `didFinish` → `NSPrintOperation` `runModal(for:)`), `Resources/Themes/*.css`, `Resources/highlight/*`, Export menu in `AppCommands.swift`.

**Verification (maps to AC5.1–AC5.5):**
- HTML export is a self-contained `.html` (no external deps) matching the theme; headings/lists/tables/code/blockquotes/links correct.
- PDF export is **multi-page**, paginated via `NSPrintOperation` (not `createPDF`), with selectable paper/margins; nothing clipped; non-blank (renders only after `didFinish`).
- Editor-only aids (Focus dim, POS, hidden markers) absent from output.
- Both reachable from File/Export; output lands at the `NSSavePanel` location.

---

## Phase 8 — Telegram share

**Goal:** one-click send to the user's own Telegram via Bot API, with setup flow + Keychain, and the `t.me` fallback.

**Files:** `Telegram/TelegramService.swift` (`sendDocument` multipart, `sendMessage` `parse_mode=HTML`, `getUpdates`), `Telegram/TelegramSetup.swift` (BotFather flow + chat-id auto-detect), `Telegram/KeychainStore.swift`, setup UI in `SettingsView.swift`, Share command in `AppCommands.swift`.

**Verification (maps to AC6.1–AC6.5):**
- Setup: enter token, message the bot, "Detect chat" finds + stores chat id; token + chat id in **Keychain** (verified absent from UserDefaults/plist).
- "Share to Telegram" sends the current `.md` via `sendDocument` to the fixed chat with **no** picker; success/failure shown.
- Rendered-text sends use HTML parse mode (no MarkdownV2 escaping errors).
- With no bot configured, falls back to `t.me/share/url` via `NSWorkspace.open` with percent-encoded title/text.
- Outgoing-network entitlement present; token never logged or written in plaintext.

---

## Phase 9 — Polish, accessibility, performance pass

**Goal:** App-Store-quality finish.

**Files:** `UI/StatusBar.swift` (fade-on-idle stats: words/chars/sentences/reading-time via `NLTokenizer`, background queue), `Support/Accessibility.swift` (Reduce Motion + Increase Contrast across all motion/noise), smart-substitution config in the engine, settings completeness in `SettingsView.swift`.

**Verification:**
- Status bar shows correct stats, adapts to selection, fades on idle, respects the always/never/fade setting.
- All motion (focus, fades, sidebar, scroll) gated by Reduce Motion; optional light-noise gated by Increase Contrast.
- Smart substitutions (curly quotes, dashes, bracket completion) work; system spellcheck/Services available.
- Full UAT pass of every acceptance criterion in `PRODUCT.md` on the user's Mac.
- Performance: 5,000-line doc edits, mode switches, focus moves, and export all without perceptible lag.

---

## Phase ordering rationale

- **Phases 1–2 front-load the only truly novel risk** (TextKit 2 marker hiding + atomic ranges + caret reveal). If they fail, the engine-protocol fallback decision happens *before* we've built features on top, and nothing downstream changes.
- **Syntax-visible mode is built before WYSIWYG hiding** within Phase 2 because it validates the shared pipeline with the least machinery.
- Everything after Phase 2 (shell, focus, sidebar, POS, export, Telegram) is comparatively low-risk integration work on a proven engine, each independently verifiable.
- Export uses the secondary cmark-gfm path, decoupled from the live engine, so it can proceed regardless of which engine implementation won Phase 2.
