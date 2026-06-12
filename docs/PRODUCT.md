# md-fire — Product Specification (v1)

> A native macOS markdown editor that fuses **Typora's seamless live WYSIWYG** with **iA Writer's focus, typography, and restraint**. Built in native Swift (SwiftUI + AppKit/TextKit). No Electron, no Tauri.

---

## 1. Vision

md-fire is a writing instrument, not a document-processing app. It should feel like the quietest, most beautiful place on your Mac to write Markdown — and, when you want it, the most fluid place to *see* your Markdown become formatted text as you type.

Two great editors already exist, each excellent at one half of this:

- **Typora** dissolves the boundary between source and preview. There is one pane; markers appear only where your caret is and melt away everywhere else. The result is WYSIWYG that never lies about the underlying Markdown.
- **iA Writer** makes the act of writing feel premium through pure subtraction: a fixed reading column, bespoke writing fonts, Focus Mode that dims everything but the active sentence, Typewriter scrolling, and an almost chromeless UI.

md-fire's bet is that these two philosophies are **not in tension** — they are two *style policies* over the same text engine. We give the user both, switchable at runtime, sharing one immutable Markdown source of truth.

### The "symbiosis" thesis — what we take from each, and why

| We take… | From | Why |
|---|---|---|
| **Seamless live WYSIWYG** (hide markers, reveal at caret, single pane) | Typora | This is the feature that makes Markdown feel like rich text without lying. It is md-fire's headline editing model. |
| **Caret-aware marker reveal** + logical caret traversal of hidden markers | Typora | Without it, WYSIWYG is just a read-only preview. The hard, signature part. |
| **CSS/native theme system, export pipeline, tables, code fences** | Typora | A complete editor needs rendered output and export that *matches* the editor. |
| **Focus Mode** (Sentence / Paragraph / Typewriter dimming) | iA Writer | The single most "premium-feel" writing aid. Works in *both* editing models. |
| **Typewriter Mode** (caret line vertically centered) | iA Writer | Calms long-form writing; pairs with Focus. |
| **iA-style syntax-visible mode** (markers shown, tastefully dimmed) | iA Writer | The second editing model the user locked in. The "honest source" mode. |
| **Bespoke writing typography** (iA Writer Mono / Duo / Quattro) + **fixed measure** (64/72/80) + centered column | iA Writer | The look that signals "premium writing tool" before you type a word. |
| **Radical chrome restraint** (hidden title bar, no formatting toolbar, slim fade-able bottom stats bar, swipe sidebar) | iA Writer | The whole aesthetic is subtraction. One accent color, gentle motion, near-white/near-black backgrounds. |
| **Grammatical Syntax Highlight** (parts of speech) | iA Writer | A differentiated "pro" editing aid that comes nearly free from Apple's NaturalLanguage framework. |

The architectural insight that makes the symbiosis cheap: **Typora-mode and iA-mode are the same `parse → map node ranges → apply attributes` pipeline.** iA-mode is "apply attributes, never hide." Typora-mode is "apply attributes, hide marker ranges, reveal the marker ranges intersecting the caret's enclosing node." Focus Mode and Typewriter Mode are orthogonal overlays that work in either. See `ARCHITECTURE.md`.

### Who it is for

The user's personal Mac (single user), built to **App-Store quality**. No multi-user, no sync service, no accounts. Quality bar = "I would happily pay for this and it never feels like a clone hack."

---

## 2. v1 Feature Spec

Each feature below has **acceptance criteria** written as testable statements. A feature is "done" when every criterion passes by manual UAT on the user's Mac.

### F1 — Dual editing model (the core)

Two runtime-switchable rendering modes over one Markdown source:

- **Live WYSIWYG mode** (Typora-style): Markdown markers (`#`, `*`, `_`, `` ` ``, `[]()`, `>`, list bullets, etc.) are hidden from layout; formatted text is shown inline. When the caret enters a block (and optionally an inline span), that element's raw markers reappear in a dim meta color so they can be edited. Inline styles render the instant the closing token is typed; block styles render on Enter or when the caret leaves the block.
- **Syntax-visible mode** (iA-style): All markers stay visible but are de-emphasized (dimmed delimiters, colored headings, monospaced code, hanging-indent list markers). The file and the rendered text are one and the same.

**Switching** is via menu + keyboard shortcut and is instantaneous and lossless (the underlying String never changes).

**Acceptance criteria**
- AC1.1 A mode toggle exists in the View menu and as a keyboard shortcut; switching modes never alters the document's bytes (verified by hashing the file before/after a round-trip).
- AC1.2 In WYSIWYG mode, typing `**bold**` renders **bold** with markers hidden as soon as the second `*` of the closing `**` is typed.
- AC1.3 In WYSIWYG mode, moving the caret into a rendered span reveals its markers in the dim meta color; moving out re-hides them.
- AC1.4 In WYSIWYG mode, Left/Right arrow keys and Backspace treat a hidden marker run as a single atomic unit (caret never lands invisibly inside hidden markers; one Backspace at a hidden boundary removes the styled construct's marker as a unit, not a phantom empty step).
- AC1.5 In syntax-visible mode, the same document shows all markers, dimmed, with headings colored and code monospaced; no markers are hidden and caret movement is ordinary.
- AC1.6 Both modes update live as you type with no perceptible lag on a 5,000-line document (styling debounced ≤30 ms; only the edited block restyled).
- AC1.7 The file on disk is always plain, valid Markdown regardless of mode.

### F2 — File sidebar + folder/file tree

A left sidebar that opens a folder as a workspace and shows a nested file/folder tree, plus a heading **Outline** for the current document.

**Acceptance criteria**
- AC2.1 "Open Folder…" sets a workspace root; the sidebar shows its nested `.md`/`.markdown`/`.txt` files and folders, expandable/collapsible.
- AC2.2 Clicking a file opens it in the editor; the active file is visually marked.
- AC2.3 The workspace folder is re-opened automatically on next launch (persisted via security-scoped bookmark) without a permission prompt.
- AC2.4 External changes to the folder (file added/removed/renamed in Finder) appear in the sidebar within ~1 s (FSEvents/`NSFilePresenter` watch).
- AC2.5 The Outline panel lists the current document's headings H1–H6 as an indented hierarchy; clicking a heading scrolls the editor to it; it updates live as headings change.
- AC2.6 The sidebar can be toggled (shown/hidden) via menu, keyboard shortcut, and a two-finger horizontal swipe.

### F3 — Focus Mode + Typewriter Mode

- **Focus Mode**: dims the whole document to a mid-gray and keeps only the active text bright, following the caret. Three scopes: **Sentence**, **Paragraph**, **Typewriter**. Toggle via menu, Focus dropdown, and shortcut.
- **Typewriter Mode**: keeps the caret's line vertically centered in the viewport; can be enabled independently of dimming. Extra top/bottom padding lets the first and last lines reach center.

Both work in **either** editing model.

**Acceptance criteria**
- AC3.1 Focus Mode dims all text except the active scope; the active scope re-computes as the caret moves.
- AC3.2 Scope = Sentence highlights only the sentence containing the caret (sentence boundaries from `NLTokenizer(unit:.sentence)`); Paragraph highlights the full caret paragraph (`paragraphRange(for:)`).
- AC3.3 The dim/brighten transition animates in ~150–200 ms ease (no bounce) and is suppressed when **Reduce Motion** is on.
- AC3.4 Typewriter Mode keeps the caret line's vertical center at the viewport's vertical center while typing and while moving the caret with arrow keys.
- AC3.5 Typewriter re-centering is **suppressed during an active mouse-drag selection** (no "screen jumping").
- AC3.6 Focus dim color and opacity are exposed as a tunable setting with a sensible default (mid-gray; light ≈ `#C6C5C2` on `#F5F6F6`, dark ≈ `#706F70` on `#1B1B1B`).
- AC3.7 Styling for Focus is applied via layout-level temporary attributes only; the document bytes are never changed.

### F4 — Theme + iA-style typography

- Two built-in themes (**Light**, **Dark**) plus a selectable accent color, anchored on iA's confirmed light values and the signature cyan-blue accent.
- Bundled writing typefaces (**iA Writer Mono / Duo / Quattro**, or a differentiated default — see non-goals/licensing) selectable in settings, with a size slider and configurable line height.
- A **fixed measure**: max characters per line of **64 / 72 / 80**, applied to the editor itself, with the text column centered and generous side gutters.
- Grammatical **Syntax Highlight** (parts of speech), editor-only, each POS independently toggleable.

**Acceptance criteria**
- AC4.1 Switching Light/Dark recolors the whole UI (background, body, dimmed, accent, selection, sidebar) using the exact hexes in `UI-DESIGN.md`; backgrounds are never pure `#FFF`/`#000`.
- AC4.2 The accent color drives caret (`insertionPointColor`), selection, and link color; default accent ≈ `#15BDEC`.
- AC4.3 The editor font, size, and line height are configurable; default is iA Writer Duo (S) (or the chosen default), ~16–18 pt, line-height multiple ~1.45–1.6.
- AC4.4 Choosing measure 64/72/80 resizes the editor's text column to that character count and re-centers it; the column re-computes on window resize and font change; a minimum gutter is kept on narrow windows.
- AC4.5 Syntax Highlight colors words by part of speech (Nouns red, Verbs blue, Adjectives brown, Adverbs purple, Conjunctions green) using `NLTagger(.lexicalClass)`; each POS can be toggled on/off independently; it is **never** written to the file, preview, or export.
- AC4.6 Syntax Highlight re-tags are debounced (~200–300 ms) and restricted to the visible/edited paragraph; no lag on long docs.
- AC4.7 The theme is authored once and consumed two ways: native text attributes for the live editor and CSS for export (they visibly match).

### F5 — Export to PDF + HTML

One markdown→themed-HTML renderer feeds both exports.

- **HTML export**: a self-contained `.html` file with the app's theme CSS inlined in a `<style>` block, including syntax-highlighted code blocks.
- **PDF export**: a properly **paginated** PDF (A4/Letter, respecting CSS page breaks and margins), rendered from the themed HTML.

**Acceptance criteria**
- AC5.1 "Export → HTML…" writes a standalone, portable `.html` (no external CSS/JS dependencies) whose appearance matches the current theme; headings, lists, tables, code blocks, blockquotes, and links all render correctly.
- AC5.2 "Export → PDF…" writes a multi-page PDF via `NSPrintOperation` (not single-page `createPDF`), with selectable paper size and margins; content paginates and is not clipped.
- AC5.3 Export always triggers only after the offscreen `WKWebView` finishes loading (`didFinish`); no blank/partial output.
- AC5.4 Editor-only aids (Focus dim, Syntax Highlight, hidden markers) never appear in exported output.
- AC5.5 Exports are reachable from the File/Export menu and produce a file at an `NSSavePanel`-chosen location.

### F6 — One-click Share to Telegram

Send the current document to the user's own Telegram via the **Bot API** as the primary path, with a zero-setup `t.me` share link fallback.

- **Primary**: `sendDocument` (the `.md` file) and/or `sendMessage` (rendered text) to a fixed chat, no chat picker. One-time setup: user creates a bot via BotFather, messages it once; the app auto-detects the chat id via `getUpdates`. Token + chat id stored in **Keychain**.
- **Fallback**: open the Telegram share sheet via a `t.me/share/url` link (URL + short text only, no file).

**Acceptance criteria**
- AC6.1 A first-run setup flow accepts a bot token, instructs the user to message the bot, then auto-detects and stores the chat id; token and chat id live in the Keychain (never UserDefaults/plist).
- AC6.2 With setup complete, a single "Share to Telegram" action sends the current `.md` file via `sendDocument` to the configured chat with **no** chat picker; success/failure is reported in-app.
- AC6.3 Rendered-text sends use `parse_mode=HTML` (or plain text), not MarkdownV2, to avoid escaping errors.
- AC6.4 If no bot is configured, the action falls back to opening a `t.me/share/url` link via `NSWorkspace.open` with the document title/text percent-encoded.
- AC6.5 The app declares the outgoing-network entitlement; no token is ever logged or written to disk in plaintext.

---

## 3. Cross-cutting quality requirements

- **Never mutate the source for presentation.** Focus, Syntax Highlight, task fading, and WYSIWYG marker hiding are all *layout-level* effects. The Markdown file is the single source of truth and round-trips byte-for-byte.
- **Premium restraint.** Exactly one accent color app-wide. Near-white/near-black backgrounds. Animations 120–200 ms ease-in-out, never bounce. Respect **Reduce Motion** and **Increase Contrast**.
- **Performance.** Incremental parse + restyle scoped to the edited block; debounced. No full-document reparse on every keystroke.
- **Accessibility.** System spellcheck, smart substitutions (curly quotes, dashes, bracket completion), VoiceOver-reachable controls, honoring system accessibility flags.

---

## 4. Non-goals / out of scope for v1

Explicitly **not** in v1 (may be reconsidered later):

- **No multi-user, accounts, or cloud sync.** Single user, local files only. (iCloud/Dropbox library browsing as a first-class feature is out; the user can point the workspace at any folder including a synced one.)
- **No Word/docx/odt/rtf/epub/LaTeX export.** Only PDF + HTML in v1. (Pandoc path is a possible later, opt-in, non-sandboxed power-user feature.)
- **No math typesetting** (LaTeX/MathJax/SwiftMath) in v1. Math fences render as plain code fences.
- **No diagram rendering** (mermaid / flowchart.js / js-sequence). Diagram fences render as plain code fences.
- **No Content Blocks / transclusion** (iA's `/path` inline file embeds, CSV→table). Nice-to-have, deferred.
- **No in-editor table editing UI** (Typora's floating table toolbar, drag-to-reorder). Tables render in preview/export and as plain GFM source in the editor; rich table editing is deferred.
- **No image paste-to-assets pipeline / uploader.**
- **No smart HTML→Markdown paste conversion** (turndown-in-WebView). Plain-text paste only in v1.
- **No theme marketplace / custom user CSS themes.** Two built-in themes + accent picker only.
- **No iOS/iPadOS target.** macOS only.
- **No App Store submission in v1** (build to App-Store *quality*, but ship as a direct/local build first; this also keeps the non-sandboxed escape hatch open for later Pandoc/Process features).

These exclusions keep v1 focused on the two things that define the product: the **dual live-render engine** and the **iA-grade writing experience**, plus the four concrete utility features (sidebar, focus/typewriter, export, Telegram).
