# md-fire — UI Design System

The look is **iA Writer's restraint**: near-white/near-black backgrounds, one accent color, a fixed centered reading column, bespoke writing type, and gentle motion. This document gives exact, implementable values.

> **Provenance note.** Only two hexes are confirmed from iA's official light-theme description: background `#F5F6F6` and body text `#424242`. Every other value comes from iA-emulating community color schemes and is **approximate** — close, tunable, to be verified against the live app. Dim opacity, default editor point size, and reading-time WPM are **not published by iA**; they ship as tunable settings with sensible defaults.

---

## 1. Color palette

### 1.1 Light theme

| Token | Hex | Notes |
|---|---|---|
| `bg` (canvas background) | **`#F5F6F6`** | Confirmed iA. Subtle noise texture optional (gate behind Reduce/Increase-Contrast). Never `#FFFFFF`. |
| `bgSidebar` | `#EFEFEF` | Slightly darker than canvas. |
| `bgElevated` (popovers, settings) | `#FFFFFF` | Allowed for elevated surfaces only. |
| `text` (body) | **`#424242`** | Confirmed iA. (Community-matched darker alt: `#1A1A1A`.) |
| `textDimmed` (Focus inactive, hidden-marker meta) | `#C6C5C2` | Mid-gray. (Range `#B8B8B8`–`#C6C5C2`.) |
| `marker` (WYSIWYG revealed / iA dimmed delimiters) | `#B0B0AE` | ~40% gray "md-char-color". |
| `lineHighlight` (current line) | `#F0F0F0` | Very subtle. Optional. |
| `selection` | `#CEE7F3` | Cyan-tinted. |
| `selectionInactive` | `#DCDCDC` | Window not key. |
| `accent` (caret, links, active) | **`#15BDEC`** | Signature cyan-blue. Alts: `#58BAE7`, `#55BBE7`. |
| `border` (window/divider) | `#E0E0E0` | Hairline. |
| `codeBg` | `#EFEFEF` | Inline + fenced code background. |

### 1.2 Dark theme

| Token | Hex | Notes |
|---|---|---|
| `bg` (canvas background) | `#1B1B1B` | Near-black charcoal. (Alt `#1D1F20`.) Never `#000000`. |
| `bgSidebar` | `#161616` | |
| `bgElevated` | `#242424` | |
| `text` (body) | `#C5C9C6` | Light gray. (Alt `#CBCCCC`.) |
| `textDimmed` (Focus inactive, meta) | `#706F70` | Mid-gray. (Alt `#525252`.) |
| `marker` | `#5E5E5E` | |
| `lineHighlight` | `#242424` | |
| `selection` | `#29434E` | Cyan-tinted; effectively `rgba(21,189,236,0.20)` over bg. |
| `selectionInactive` | `#464646` | |
| `accent` | `#15BDEC` | Same accent both themes. |
| `border` | `#2A2A2A` | |
| `codeBg` | `#242424` | |

### 1.3 Accent palette (selectable highlight)

Default **cyan-blue `#15BDEC`**. Optional swatches (drive caret/selection/links only): yellow, orange, pink, purple, blue, green. One accent active app-wide at a time.

### 1.4 Parts-of-speech (Syntax Highlight) — editor only

Current iA mapping. Approximate hexes (no official values); tune for contrast on both themes.

| Part of speech | Color name | Hex |
|---|---|---|
| Nouns | red | `#C8402F` |
| Verbs | blue | `#2E7DD1` |
| Adjectives | brown | `#9A6A3A` |
| Adverbs | purple | `#8E5BA6` |
| Conjunctions | green | `#4F9A4F` |

Never written to file, preview, or export. Each POS independently toggleable.

---

## 2. Typography

### 2.1 Fonts

- **Editor default:** `iA Writer Duo S` (duospace) — or a differentiated default if shipping without iA fonts (see licensing in ARCHITECTURE.md). Selectable: **Mono** (1 width), **Duo** (m/M/w/W get ~50% extra), **Quattro** (4 widths, near-proportional).
- **PostScript family names:** `iA Writer Mono`, `iA Writer Duo`, `iA Writer Duo S`, `iA Writer Quattro`, `iA Writer QuattroS`.
- **Fallback chain:** `iA Writer Duo S` → `SF Mono` → `Menlo` → `Monaco` → system monospaced.
- **UI chrome font** (sidebar, status bar, menus): `SF Pro` (system) — keep the bespoke font for *writing surface only*.
- **Code font** (fenced/inline code): same as editor mono, or `SF Mono` if editor font is Duo/Quattro.

### 2.2 Sizes & metrics (defaults, all tunable)

| Property | Default | Range |
|---|---|---|
| Editor body size | **17 pt** | slider 12–28 pt |
| Line height (`lineHeightMultiple`) | **1.5** | 1.35–1.7 |
| Paragraph spacing | 0.35 × line height | — |
| Hyphenation | **off** | — |

### 2.3 Heading scale (WYSIWYG rendered + iA syntax-visible coloring)

Relative to body size `S` (default 17 pt):

| Element | Size | Weight | Color |
|---|---|---|---|
| H1 | `1.8 S` (≈30.6) | Bold | `text` |
| H2 | `1.5 S` (≈25.5) | Bold | `text` |
| H3 | `1.3 S` (≈22.1) | Semibold | `text` |
| H4 | `1.15 S` (≈19.5) | Semibold | `text` |
| H5 | `1.0 S` | Semibold | `text` |
| H6 | `1.0 S` | Semibold | `textDimmed` |
| Body / paragraph | `1.0 S` | Regular | `text` |
| Bold | `1.0 S` | Bold | `text` |
| Italic | `1.0 S` | Italic | `text` |
| Inline code | `0.95 S` | Mono | `text` on `codeBg` |
| Blockquote | `1.0 S` | Regular italic | `textDimmed`, 3 pt accent bar |
| Link | `1.0 S` | Regular | `accent`, underline on hover |

### 2.4 Fixed measure (the reading column)

- Char-count options: **64 / 72 / 80** (segmented control). Default **72**.
- Column width = `charCount × advanceWidth("0" in current font)`. For Duo/Quattro (not strictly mono), use the **average advance** or a fixed em multiple, not a single glyph.
- Center the column: `textContainer.size.width = columnWidth`; `textContainerInset.left = textContainerInset.right = max(minGutter, (viewWidth − columnWidth) / 2)`.
- **Minimum side gutter:** 24 pt (keep even on narrow windows).
- Recompute on window resize, font change, and measure change.

---

## 3. Spacing scale

A 4 pt base grid.

| Token | Value |
|---|---|
| `space-0` | 0 |
| `space-1` | 4 pt |
| `space-2` | 8 pt |
| `space-3` | 12 pt |
| `space-4` | 16 pt |
| `space-5` | 24 pt |
| `space-6` | 32 pt |
| `space-8` | 48 pt |

Applied: sidebar row padding `space-2`/`space-3`; status bar padding `space-2` vertical, `space-4` horizontal; editor canvas top/bottom inset (non-typewriter) `space-6`; settings group spacing `space-5`.

---

## 4. Layout spec

```
┌───────────────────────────────────────────────────────────────────────┐
│  (hidden title bar — titleVisibility .hidden, titlebarAppearsTransparent) │
├──────────────┬────────────────────────────────────────────────────────┤
│              │                                                          │
│   SIDEBAR    │                  EDITOR CANVAS                           │
│  (collapsible)│         ┌──────── measure column ────────┐              │
│              │  gutter  │  centered reading column        │  gutter      │
│  • File Tree │          │  (64/72/80 chars)               │              │
│  • Outline   │          │                                 │              │
│              │          └─────────────────────────────────┘              │
│              │                                                          │
├──────────────┴────────────────────────────────────────────────────────┤
│  STATUS BAR (slim, fade-on-idle): words · chars · sentences · reading t │
└───────────────────────────────────────────────────────────────────────┘
```

### 4.1 Window / chrome

- `window.titleVisibility = .hidden`, `titlebarAppearsTransparent = true`. No formatting toolbar. Traffic lights overlay the canvas/sidebar top-left.
- Toolbar style: none or `.unifiedCompact`. The *only* persistent chrome is the bottom status bar.
- Default window size: **1000 × 720**; min **640 × 480**.

### 4.2 Sidebar (`NavigationSplitView` column)

- Width: default **260 pt**, range 200–360, resizable.
- Background `bgSidebar`. Hairline `border` on the canvas edge.
- Three stacked sections: **File Tree** (workspace root, nested, disclosure triangles), **Outline** (current doc headings, indented by level), optional **Files** flat list. Sections collapsible.
- Row height 28 pt; active file row background `lineHighlight` + accent text; hover background a 4% accent tint.
- Toggle: menu + `⌘⌥S` (suggested) + **two-finger horizontal swipe** (`NSEvent` scroll/swipe). Slide animation 180 ms ease, gated by Reduce Motion.

### 4.3 Editor canvas

- Background `bg`. Hosts the engine `NSView` (the TextKit 2 editor).
- Reading column centered per §2.4. Caret = `accent` (`insertionPointColor`). Selection = `selection`.
- Smart substitutions on: `automaticQuoteSubstitutionEnabled`, `automaticDashSubstitutionEnabled`, bracket completion.
- Non-typewriter top/bottom inset `space-6`. In Typewriter mode, top/bottom inset = half the viewport height (so first/last lines can center).

### 4.4 Top toolbar

- **None by default.** A `Focus` dropdown (Sentence / Paragraph / Typewriter / Off) and the mode switch live in the menu bar (and optionally a single fade-in title-area control). No button row.

### 4.5 Bottom status bar

- Slim `HStack` pinned to the editor bottom (a SwiftUI view, **not** an `NSToolbar`). Height **24 pt**. Background `bg` (or a 2% darker tint), hairline top `border`.
- Right-aligned stats (default layout): **words · characters · sentences · estimated reading time**. Stats adapt to selection (selected range vs whole doc). Computed via `NLTokenizer(unit:.word)` (count) and `NLTokenizer(unit:.sentence)`; reading time = words ÷ WPM (default **220 wpm**, tunable, marked approximate). Recompute debounced on text/selection change, off the main thread.
- Fade behavior: **always show / never show / fade-on-idle** (default fade). Opacity fades via 150–200 ms `CABasicAnimation` tied to mouse-idle + typing state; gated by Reduce Motion.

---

## 5. Focus Mode & Typewriter visuals

### 5.1 Focus Mode (dimming)

- Active scope text uses `text`; inactive text uses `textDimmed` (light `#C6C5C2` on `#F5F6F6`; dark `#706F70` on `#1B1B1B`). Applied via **layout-level temporary attributes** (never mutates the buffer).
- **Dim opacity is a tunable setting** (iA does not publish it). Default: dimmed text rendered at the `textDimmed` hex (≈ 45–55% perceived contrast vs body). Expose a 0–100% "Focus dim" slider mapping to interpolation between `text` and `bg`.
- Transition: brighten/dim cross-fades over **150–200 ms** (ease-in-out, no bounce), implemented by easing the temp-attribute color via `CADisplayLink`/timer (temp attributes don't animate natively). Suppressed entirely under **Reduce Motion** (instant swap).
- Scope detection: **Sentence** = `NLTokenizer(unit:.sentence)` token containing the caret within the caret paragraph; **Paragraph** = `(text as NSString).paragraphRange(for: selectedRange)`. Recompute on `textViewDidChangeSelection`.

### 5.2 Typewriter Mode (centering)

- Keep the caret line's `midY` aligned to the viewport `midY`. Get the line rect via `NSLayoutManager`/TextKit 2 line-fragment bounding rect; scroll so that rect centers.
- Add top/bottom `textContainerInset` = half the viewport height so the first and last lines can reach center.
- Disable implicit scroll animation during fast typing (`NSAnimationContext` duration 0); allow a short ~120 ms ease on caret *jumps*.
- **Suppress re-centering during an active mouse-drag selection** (prevents the documented "screen jumping"). Can be enabled independently of Focus dimming.

---

## 6. Component inventory

| Component | Spec |
|---|---|
| **Sidebar file row** | 28 pt height, disclosure triangle, icon + name, active = `lineHighlight` + accent text. |
| **Outline row** | Indented by heading level (12 pt per level), name truncated, click → scroll. |
| **Editor caret** | `accent`, standard blink, 2 pt wide. |
| **Selection** | `selection` / `selectionInactive`. |
| **Revealed marker (WYSIWYG)** | `marker` color, same size as content. |
| **Dimmed marker (iA mode)** | `marker` color, reduced weight. |
| **Inline code chip** | `codeBg` background, 3 pt horizontal padding, 2 pt corner radius, mono. |
| **Fenced code block** | `codeBg` background, 8 pt inset, language label bottom-right (popup), Highlightr-colored. |
| **Blockquote** | 3 pt `accent` left bar, `textDimmed` italic, `space-3` left inset. |
| **Task checkbox** | `- [ ]`/`- [x]`; checked items strikethrough + faded via temp attrs. |
| **Status bar stat group** | SF Pro 11 pt, `textDimmed`, dot separators `·`. |
| **Focus dropdown** | Menu: Off / Sentence / Paragraph / Typewriter; checkmark on active. |
| **Mode switch** | Menu + shortcut: "Live Preview" ↔ "Source / Syntax". |
| **Settings panel** | `bgElevated`, grouped sections (Theme, Typography, Measure, Focus, Telegram), standard macOS form metrics. |
| **Telegram setup sheet** | Token field (secure), "Message your bot" instruction, "Detect chat" button, status row. |
| **Export sheet** | `NSSavePanel` + format/paper/margin options for PDF. |

---

## 7. Motion

- Allowed: Focus dim (150–200 ms), toolbar/status fade (150–200 ms), sidebar slide (180 ms), caret-jump scroll (~120 ms). All **ease-in-out, never bounce**.
- All motion gated by `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` → instant, no animation.
- No animation during fast typing (typewriter scroll uses duration 0).

---

## 8. Premium-restraint aesthetic guidelines

1. **Subtraction first.** No formatting toolbar, no popups that aren't essential, hidden title bar. The writing surface dominates.
2. **One accent color, app-wide.** Caret, links, selection, active states all derive from the single accent (`#15BDEC` default). Nothing else is colorful except editor-only POS highlighting.
3. **Never pure black/white.** Backgrounds are `#F5F6F6` / `#1B1B1B`. Optional faint noise on light, gated by accessibility.
4. **The measure is sacred.** The fixed, centered reading column is applied to the editor itself — not just preview. This is what signals "iA" before a word is typed.
5. **Type does the heavy lifting.** Bespoke writing font, generous line height, large word spacing, monospaced punctuation rhythm. Consistent paragraph spacing; no hyphenation.
6. **Gentle, sparse motion.** 120–200 ms eases only where they aid comprehension (focus, fades, slides). Respect Reduce Motion and Increase Contrast everywhere.
7. **Honest source.** Presentation effects (focus, POS, hidden markers, task fade) never touch the file. What you save is plain Markdown.
8. **Attribution & differentiation.** Credit iA for the fonts if bundled; consider a differentiated default to stay clearly on the right side of "inspired by, not a knockoff."
