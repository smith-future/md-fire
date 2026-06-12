# md-fire — Architecture

This document fixes the technical architecture for md-fire v1. It leads with the single highest-risk decision — the rendering engine — then gives the module tree, data flow, the dual-mode engine design, key types/protocols, chosen libraries, and a feature→architecture map.

---

## 1. Rendering-engine decision (lead)

### Decision

**Build the live editor on a native `NSTextView` in TextKit 2 mode**, wrapped in `NSViewRepresentable`, with a single parse→map→style pipeline driven by **tree-sitter** as the primary incremental parser. Hide markup (Typora mode) via a custom `NSTextLayoutFragment` and atomic-range selection handling.

**But ship behind an engine protocol (`MarkdownRenderingEngine`)**, and de-risk the schedule by proving the native engine on a thin vertical slice *first*; keep a **WKWebView + CodeMirror 6** engine as a documented fallback that can be slotted behind the same protocol if TextKit 2 edge cases prove too costly.

### Rationale (drawn from the research)

The locked decision is "native Swift, no Electron/Tauri," so the live editor must ultimately be native. The research is blunt about the trade:

- **The two modes are one engine.** The decisive insight: Typora-mode and iA-mode differ only in two booleans — *does it hide markers?* and *does it reveal at caret?* — over the same `parse → map node ranges → apply attributes` pipeline. This means we do **not** write two engines; we write one styler and two `StylePolicy` values. iA-mode ("apply attributes, never hide") is trivial once node→range mapping exists. Typora-mode adds hiding + caret-reveal + atomic ranges.

- **Why TextKit 2 (not SwiftUI `TextEditor`, not contenteditable WKWebView for editing).** SwiftUI's `TextEditor`/`Text(markdown:)` cannot do per-range token hiding, attachments, caret/scroll control, or temporary attributes. A contenteditable WKWebView (Typora's own approach) costs native IME, undo, accessibility, Services, Writing Tools, and perf. TextKit 2 (`NSTextLayoutManager` + `NSTextContentStorage`) is Apple's strategic text direction (WWDC26 session 370) and is the only path that gives us native text behavior *and* the custom layout we need.

- **Why tree-sitter is the primary parser.** It is the only realistic option for true incremental, per-keystroke reparsing with directly usable **byte ranges**. `swift-markdown` (cmark-gfm) re-parses the whole document, its `MarkupFormatter` is non-idempotent (wrong for round-tripping the user's exact source), and its `SourceLocation`s are 1-indexed line + UTF-8 column requiring an O(n) per-lookup conversion — too slow and awkward for the live keystroke path. So tree-sitter for the live path; `swift-markdown`/cmark-gfm kept only as a **secondary** engine for export and as a correctness oracle in tests.

- **Honest risk acknowledgment.** TextKit 2 is still rough for editing UIs (per the STTextView author, 2025–26): silent fallback to TextKit 1 if any TextKit-1 API is touched; flaky rendering attributes pre-macOS 13; viewport-height "jiggle"; `drawInsertionPoint` not firing. We mitigate by (a) using **STTextView** (`krzyzanowskim/STTextView`) as the base view to avoid re-deriving TextKit 2 quirks, (b) hiding markers via the **Apple DTS-recommended** custom `NSTextLayoutFragment` rather than the broken clear-color hack, (c) implementing **atomic ranges** by overriding selection/movement (porting CodeMirror 6's `atomicRanges` model), and (d) keeping the WKWebView/CM6 engine ready behind the protocol.

### Hiding markup — two-stage plan

1. **Stage 1 (fast demo):** attribute-based collapse — but `foregroundColor = .clear` alone leaves the glyph's advance width, so the caret can land in the gap. Pair it immediately with atomic-range selection snapping. Use only to validate the slice.
2. **Stage 2 (correct):** custom `NSTextLayoutFragment` subclass returned from `NSTextLayoutManagerDelegate.textLayoutManager(_:textLayoutFragmentFor:in:)` that **omits hidden glyph runs from drawing and reports collapsed bounds**, plus `NSTextContentManagerDelegate` to skip hidden elements where appropriate. Always paired with atomic selection handling.

### TextKit 2 hygiene (non-negotiable rules)

- Let the text view lazily create `NSTextLayoutManager` + `NSTextContentStorage`. **Never** touch `.layoutManager` (TextKit 1) or the view silently drops to TextKit 1 and our custom layout breaks. Add a lint/CI grep for accidental TextKit-1 access.
- Apply styling attributes to `NSTextContentStorage.attributedString` and/or draw in the custom fragment — **do not** rely solely on `NSTextLayoutManager` rendering attributes (historically flaky).
- Convert tree-sitter **UTF-8 byte offsets** to **UTF-16 `NSRange`** explicitly (NSString is UTF-16); cache a line-start offset table. Test with emoji/CJK/accents.

---

## 2. Module / file tree

A single Xcode `.app` project (see `BUILD-PLAN.md` Phase 0), Swift packages for the heavy parsing/highlighting deps. Source organized by domain.

```
md-fire/
├── md-fire.xcodeproj
├── Package.swift                      # local SPM for app-internal targets (optional) + remote deps
├── docs/                              # PRODUCT.md, ARCHITECTURE.md, UI-DESIGN.md, BUILD-PLAN.md
├── Resources/
│   ├── Fonts/                         # iA Writer Mono/Duo/Quattro TTFs (or differentiated default) + LICENSE/attribution
│   ├── Themes/
│   │   ├── light.css                  # export CSS, authored from the same theme source
│   │   └── dark.css
│   ├── highlight/                     # bundled highlight.js + theme CSS for export code blocks
│   └── Grammars/                      # tree-sitter-markdown / -inline compiled grammars (via SPM products)
├── Sources/
│   └── MdFire/
│       ├── App/
│       │   ├── MdFireApp.swift              # @main, App scene, Commands (menus + shortcuts)
│       │   ├── AppCommands.swift            # SwiftUI Commands: View/Format/Focus/Export/Share menus
│       │   └── AppEnvironment.swift         # DI container: settings, theme, services
│       ├── Document/
│       │   ├── MarkdownDocument.swift       # the immutable-source model (String + metadata)
│       │   ├── DocumentStore.swift          # open/save, security-scoped bookmarks
│       │   └── WorkspaceModel.swift         # workspace root, file tree, FSEvents watcher
│       ├── Engine/                          # ── the rendering engine ──
│       │   ├── MarkdownRenderingEngine.swift   # protocol (the swap boundary)
│       │   ├── TextKitEngine/
│       │   │   ├── TextKitEngine.swift         # NSViewRepresentable wrapping STTextView
│       │   │   ├── EngineCoordinator.swift     # selection/scroll/edit delegate glue
│       │   │   ├── StylePolicy.swift           # protocol + LiveWYSIWYG / SyntaxVisible impls
│       │   │   ├── Styler.swift                # consumes parse intents → applies attributes
│       │   │   ├── HiddenMarkupFragment.swift  # custom NSTextLayoutFragment (Stage 2 hiding)
│       │   │   ├── AtomicRanges.swift          # caret/selection snapping over hidden ranges
│       │   │   ├── CaretReveal.swift           # Typora reveal-at-caret rule (block/inline scope)
│       │   │   └── RangeMapping.swift          # UTF-8 byte ↔ UTF-16 NSRange, line-start cache
│       │   └── WebEngine/                      # fallback (stubbed in v1, behind same protocol)
│       │       └── WebViewEngine.swift         # WKWebView + CodeMirror 6 (kenforthewin/atomic-editor model)
│       ├── Parser/
│       │   ├── TreeSitterParser.swift          # primary: incremental reparse, emits SyntaxNode ranges
│       │   ├── SyntaxNode.swift                # node model (role + NSRange + marker subranges)
│       │   └── CmarkExportParser.swift         # secondary: swift-markdown AST for export + tests
│       ├── Overlays/                           # mode-agnostic visual overlays
│       │   ├── FocusModeController.swift        # Sentence/Paragraph/Typewriter dimming (temp attrs)
│       │   ├── TypewriterController.swift        # caret-line centering + scroll lock + padding
│       │   ├── SyntaxHighlightController.swift   # NaturalLanguage POS coloring (temp attrs, toggleable)
│       │   └── TaskFadeController.swift          # strikethrough/fade completed - [x] tasks
│       ├── Theme/
│       │   ├── Theme.swift                      # Codable theme: colors/fonts/spacing (light+dark)
│       │   ├── ThemePalette.swift               # exact hexes from UI-DESIGN.md
│       │   ├── Typography.swift                 # font families, sizes, line height, measure math
│       │   └── ThemeCSS.swift                   # theme → export CSS string (matches native attrs)
│       ├── UI/
│       │   ├── RootView.swift                   # NavigationSplitView: sidebar + editor + status bar
│       │   ├── Sidebar/
│       │   │   ├── FileTreeView.swift
│       │   │   ├── OutlineView.swift
│       │   │   └── SidebarSwipe.swift           # two-finger swipe toggle
│       │   ├── EditorCanvas.swift               # hosts the engine view, applies measure/insets
│       │   ├── StatusBar.swift                  # word/char/sentence/reading-time, fade-on-idle
│       │   └── Settings/
│       │       └── SettingsView.swift           # theme, font, measure, focus scope, telegram setup
│       ├── Export/
│       │   ├── HTMLRenderer.swift               # markdown → themed standalone HTML (shared step)
│       │   ├── PDFExporter.swift                # WKWebView load → NSPrintOperation (paginated)
│       │   └── HTMLExporter.swift               # write standalone .html
│       ├── Telegram/
│       │   ├── TelegramService.swift            # sendDocument / sendMessage / getUpdates
│       │   ├── TelegramSetup.swift              # BotFather flow, chat-id auto-detect
│       │   └── KeychainStore.swift              # token + chat id in Keychain
│       └── Support/
│           ├── Settings.swift                   # @AppStorage-backed user settings
│           ├── Debouncer.swift                  # debounce for parse/restyle/stats
│           └── Accessibility.swift              # ReduceMotion / IncreaseContrast helpers
└── Tests/
    └── MdFireTests/
        ├── RangeMappingTests.swift             # UTF-8↔UTF-16, multibyte
        ├── ParserTests.swift                   # tree-sitter vs cmark-gfm oracle
        ├── StylePolicyTests.swift              # WYSIWYG vs SyntaxVisible intents
        ├── RoundTripTests.swift                # mode-switch byte-stability
        └── ExportTests.swift                   # HTML/PDF non-empty + theme match
```

---

## 3. Data flow: edit → parse → attribute → layout

```
User keystroke
   │
   ▼
NSTextStorage edit  ──(NSTextStorageDelegate.didProcessEditing range/changeInLength)──►  EngineCoordinator
   │                                                                                          │
   │  String stays the single source of truth (never mutated for presentation)               │
   ▼                                                                                          ▼
Debouncer (~10–30 ms)                                                          TreeSitterParser.applyEdit()
   │                                                                          (Tree.edit(InputEdit) → reparse
   ▼                                                                           reusing old tree; changed subtree only)
Scope = edited block + enclosing element                                                     │
                                                                                              ▼
                                                                          Walk changed nodes → [SyntaxNode]
                                                                          (role + content NSRange + marker subranges)
                                                                                              │
                                                                                              ▼
                                                                          Styler.apply(nodes, policy:)
                                                                                              │
                            ┌─────────────────────────────────────────────────────────────────┘
                            ▼
   StylePolicy decides presentation:
     • SyntaxVisible:   content attrs + dim marker ranges (no hide)
     • LiveWYSIWYG:     content attrs + mark marker ranges hidden
                        + CaretReveal un-hides markers of the caret's enclosing node
                        + AtomicRanges registers hidden runs as atomic
                            │
                            ▼
   Attributes written to NSTextContentStorage.attributedString in beginEditing()/endEditing()
   (applied after layout, on textDidChange — never inside processEditing)
                            │
                            ▼
   TextKit 2 layout:
     • HiddenMarkupFragment omits hidden glyph runs from draw + reports collapsed bounds
     • Overlays applied as layout-level temporary attributes:
         FocusMode (dim non-active), Typewriter (scroll-lock), SyntaxHighlight (POS), TaskFade
                            │
                            ▼
                        Rendered editor
```

Selection-change path (caret moves, no text change):

```
selectionDidChange / willChangeSelection
   │
   ├─► CaretReveal: recompute enclosing node, reveal/restore its markers (WYSIWYG only)
   ├─► AtomicRanges: snap selection out of hidden ranges (WYSIWYG only)
   ├─► FocusModeController: recompute active sentence/paragraph, re-dim (both modes)
   ├─► TypewriterController: re-center caret line (suppress during drag-select)
   └─► StatusBar: recompute stats for selection vs whole doc (debounced, background queue)
```

Export path (separate, low-frequency, cmark-gfm):

```
MarkdownDocument.string ─► CmarkExportParser (swift-markdown) ─► HTMLRenderer (themed standalone HTML)
                                                                      │
                              ┌───────────────────────────────────────┴──────────────┐
                              ▼                                                        ▼
                       HTMLExporter (write .html)                 PDFExporter: load HTML in offscreen WKWebView
                                                                  → on didFinish → NSPrintOperation (paginated PDF)
```

---

## 4. Dual-mode engine design (how WYSIWYG and syntax-visible share one model)

The whole point: **one pipeline, two policy values.** The document model, parser, styler, and all overlays are mode-agnostic. Mode lives entirely in a `StylePolicy`.

```swift
enum RenderMode { case liveWYSIWYG, syntaxVisible }

/// A syntactic element with precise ranges. role distinguishes content vs the marker
/// characters (the *, _, #, `, [](), >, list bullet runs) so we can style/hide them separately.
struct SyntaxNode {
    enum Role { case heading(level: Int), emphasis, strong, codeSpan, codeBlock,
                     link, blockquote, listItem, taskItem(checked: Bool), paragraph, text, thematicBreak }
    let role: Role
    let contentRange: NSRange      // the rendered text
    let markerRanges: [NSRange]    // delimiter runs (hidden in WYSIWYG, dimmed in SyntaxVisible)
    let nodeRange: NSRange         // full span (content + markers)
}

/// The only thing that differs between the two editing models.
protocol StylePolicy {
    var hidesMarkup: Bool { get }          // WYSIWYG: true, iA: false
    var revealsAtCaret: Bool { get }       // WYSIWYG: true, iA: false
    func contentAttributes(for node: SyntaxNode, theme: Theme) -> [NSAttributedString.Key: Any]
    func markerAttributes(for node: SyntaxNode, theme: Theme) -> [NSAttributedString.Key: Any]
}

struct LiveWYSIWYGPolicy: StylePolicy {     // Typora model
    let hidesMarkup = true
    let revealsAtCaret = true
    // contentAttributes: full rendered styling (heading size/weight, bold, italic, code mono, etc.)
    // markerAttributes:  the .hidden custom attribute consumed by HiddenMarkupFragment
}

struct SyntaxVisiblePolicy: StylePolicy {   // iA model
    let hidesMarkup = false
    let revealsAtCaret = false
    // contentAttributes: tasteful styling (colored headings, mono code, hanging indents)
    // markerAttributes:  dim foregroundColor (e.g. md-char-color), reduced weight — never hidden
}
```

`Styler` is identical for both: it asks the policy for content + marker attributes and applies them. `CaretReveal` and `AtomicRanges` are *gated* on `policy.revealsAtCaret` / `policy.hidesMarkup`, so in syntax-visible mode they are simply no-ops. Switching mode = swap the policy value and re-run `Styler` over the visible range. The `String` is never touched, so AC1.1 (byte-stable round-trip) holds for free.

**The engine swap boundary** (so the WebView fallback can replace the native engine without touching the rest of the app):

```swift
protocol MarkdownRenderingEngine: AnyObject {
    var nsView: NSView { get }
    func setText(_ markdown: String)
    var text: String { get }
    func setMode(_ mode: RenderMode)
    func setTheme(_ theme: Theme)
    func setFocus(_ focus: FocusConfig)        // scope + on/off
    func setTypewriter(_ enabled: Bool)
    func setSyntaxHighlight(_ pos: Set<NLTag>)  // empty = off
    var onChange: ((String) -> Void)? { get set }
    var onSelectionChange: ((NSRange) -> Void)? { get set }
}
```

`TextKitEngine` is the v1 implementation; `WebViewEngine` is stubbed behind the same protocol as the documented fallback.

---

## 5. Key types & protocols (summary)

| Type / protocol | Responsibility |
|---|---|
| `MarkdownRenderingEngine` | Swap boundary between native and WebView engines. |
| `RenderMode` / `StylePolicy` / `LiveWYSIWYGPolicy` / `SyntaxVisiblePolicy` | The dual-mode core; presentation differences only. |
| `SyntaxNode` | Parser output: role + content/marker/full ranges. |
| `TreeSitterParser` | Primary incremental parse; emits `[SyntaxNode]` for changed region. |
| `RangeMapping` | UTF-8 byte ↔ UTF-16 NSRange, cached line-start table. |
| `Styler` | Applies policy attributes to content storage. |
| `HiddenMarkupFragment` | Custom `NSTextLayoutFragment` omitting hidden glyphs (Stage-2 hiding). |
| `AtomicRanges` | Snaps caret/selection/deletion over hidden runs. |
| `CaretReveal` | Reveal-at-caret rule (enclosing block, optionally inline). |
| `FocusModeController` | Sentence/Paragraph/Typewriter dimming via temp attributes. |
| `TypewriterController` | Caret-line centering, scroll lock, top/bottom padding. |
| `SyntaxHighlightController` | `NLTagger(.lexicalClass)` POS coloring, per-POS toggle. |
| `Theme` / `ThemePalette` / `Typography` / `ThemeCSS` | One theme source → native attrs + export CSS. |
| `HTMLRenderer` | markdown → themed standalone HTML (shared by both exports). |
| `PDFExporter` / `HTMLExporter` | Paginated PDF (NSPrintOperation) and standalone HTML. |
| `TelegramService` / `TelegramSetup` / `KeychainStore` | Bot API send + chat-id auto-detect + Keychain. |
| `WorkspaceModel` / `DocumentStore` | File tree, FSEvents watch, security-scoped bookmarks. |

---

## 6. Chosen libraries (name · version · why)

| Library | Version (pin) | Role | Why |
|---|---|---|---|
| **STTextView** (`krzyzanowskim/STTextView`) | `2.3.x` (≥ 2.3.10) | Base TextKit 2 NSTextView | Avoids re-deriving TextKit 2 quirks; macOS 14+, plugin system incl. Neon. Use as the editor view shell. |
| **SwiftTreeSitter** (`ChimeHQ/SwiftTreeSitter`) | latest tagged (pin exact) | tree-sitter Swift wrapper | Incremental parse with byte ranges; `Tree.edit()` reuse. |
| **Neon** (`ChimeHQ/Neon`) | latest tagged (pin exact) | tree-sitter client | `TreeSitterClient` hybrid sync/async + `highlights.scm`; wraps the edit→reparse loop. |
| **tree-sitter-markdown** + **tree-sitter-markdown-inline** grammars | pinned commit | Markdown grammars (block + inline) | Split grammars give precise block/inline node ranges for marker isolation. |
| **swift-markdown** (`swiftlang/swift-markdown`) | latest tagged | Secondary/export parser + test oracle | cmark-gfm conformance for export & GFM edge cases; `Document(parsing:)` AST. |
| **Down** (`johnxnguyen/Down`) | `0.11.x` | (alt) markdown→HTML for export | Fast cmark-based `toHTML`; use if walking swift-markdown's AST to HTML is too slow to ship. Pick one of swift-markdown-walk vs Down for `HTMLRenderer`. |
| **Highlightr** (`raspu/Highlightr`) | `2.x` | Code highlighting | Highlight.js wrapper, 180+ languages; used for code fences in editor and export. (Splash is the Swift-only alternative if a smaller dep is preferred.) |
| **highlight.js** CSS/JS (bundled resource) | pin a release | Export code-block highlighting | Self-contained export needs inlined highlight CSS. |
| Apple **NaturalLanguage** | system | POS tagging + sentence/word tokenization | `NLTagger(.lexicalClass)` for Syntax Highlight; `NLTokenizer` for sentence/word counts. Covers the same languages iA supports; no grammar engine to ship. |
| Apple **WebKit** (`WKWebView`) | system | Export rendering (+ fallback engine host) | Themed HTML render for PDF/HTML export; future home of the CM6 fallback engine. |
| Apple **AppKit / TextKit 2** | system | Editor, printing, sharing | `NSTextLayoutManager`, `NSTextContentStorage`, `NSPrintOperation`, `NSWorkspace`. |

> **Note on the WebView fallback:** if it is ever activated, the stack is **WKWebView + CodeMirror 6** modeling `kenforthewin/atomic-editor` (`inlinePreview`, `atomicMarkdownSyntax`, mouse-freeze guard, O(change) decoration rebuilds). Not a v1 dependency; documented so the protocol boundary is real.

> **Font licensing:** the iA fonts (`github.com/iaolo/iA-Fonts`) are open source but iA asks for credit and "no knockoff." Bundle with clear attribution, or default to a differentiated writing font and offer the iA fonts as an opt-in. Register via `CTFontManagerRegisterFontsForURL` or `ATSApplicationFontsPath`; expose as `Font.custom("iA Writer Duo S", size:)`.

---

## 7. Feature → architecture map

| v1 feature | Primary modules | Key APIs / notes |
|---|---|---|
| **F1 Dual editing model** | `Engine/*`, `Parser/*`, `StylePolicy` | TextKit 2 `NSTextView` (STTextView); tree-sitter incremental; `LiveWYSIWYGPolicy` vs `SyntaxVisiblePolicy`; `HiddenMarkupFragment` + `AtomicRanges` + `CaretReveal`. All presentation via attributes; String immutable. |
| **F2 Sidebar + tree + outline** | `UI/Sidebar/*`, `WorkspaceModel`, `DocumentStore` | `NavigationSplitView`; recursive `FileManager` model; FSEvents/`NSFilePresenter` watch; security-scoped bookmarks; Outline from the same parse (Heading nodes → `scrollRangeToVisible`); two-finger swipe toggle. |
| **F3 Focus + Typewriter** | `Overlays/FocusModeController`, `Overlays/TypewriterController` | `NLTokenizer(unit:.sentence)` + `paragraphRange(for:)`; temp attributes for dim; `boundingRect(forGlyphRange:)` → scroll center; suppress during drag-select; 150–200 ms ease, gated by Reduce Motion. Works in both modes. |
| **F4 Theme + typography + measure + POS** | `Theme/*`, `EditorCanvas`, `Overlays/SyntaxHighlightController` | Theme struct → native attrs + `ThemeCSS`; bundled fonts; measure = char-count × glyph advance → `textContainer.width` + centered `textContainerInset`; `NLTagger(.lexicalClass)` POS coloring (temp attrs, per-POS `Set<NLTag>`), editor-only. |
| **F5 Export PDF + HTML** | `Export/HTMLRenderer`, `PDFExporter`, `HTMLExporter`, `CmarkExportParser`, `ThemeCSS` | swift-markdown/Down → themed standalone HTML; PDF via offscreen `WKWebView` load → on `didFinish` → `NSPrintOperation` `runModal(for:)` with `NSPrintSaveJob` (paginated, **not** `createPDF`). |
| **F6 Telegram share** | `Telegram/*`, `KeychainStore` | `URLSession` `sendDocument` (multipart) / `sendMessage` (`parse_mode=HTML`); chat-id via `getUpdates`; Keychain storage; outgoing-network entitlement; `t.me/share/url` fallback via `NSWorkspace.open`. |

---

## 8. Concurrency, performance, sandbox

- **Concurrency:** parse + style on the main actor's debounced loop for correctness with the text storage, but offload POS tagging, word counts, and export rendering to background queues/`Task`s; marshal attribute application back to main.
- **Performance:** reparse only the changed subtree (tree-sitter); restyle only the edited block + enclosing element; batch attribute writes in `begin/endEditing`; cache the line-start offset table; cache code-block highlight results by fence hash.
- **Sandbox:** v1 ships as a direct/local build (App-Store *quality*, not necessarily sandboxed-submitted). This keeps a future Pandoc/Process path open and avoids security-scoped friction beyond workspace bookmarks. Workspace folder access persists via security-scoped bookmarks regardless. Telegram needs the outgoing-network entitlement.
