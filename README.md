# md-fire

A native macOS markdown editor that fuses **Typora's seamless live WYSIWYG** with
**iA Writer's focus, typography, and restraint**. Built in native Swift (SwiftUI +
AppKit/TextKit 2). No Electron, no Tauri.

> One Markdown source of truth. Two switchable editing models (live WYSIWYG ↔
> syntax-visible) that are the *same* render pipeline with two booleans. Presentation
> effects never touch the file — what you save is always plain Markdown.

## Status

**Phase 0 — scaffold.** Runnable empty shell. See `docs/BUILD-PLAN.md` for the roadmap.

## Design docs

- [`docs/PRODUCT.md`](docs/PRODUCT.md) — vision, v1 feature spec, acceptance criteria, non-goals
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — rendering-engine decision, module tree, dual-mode design
- [`docs/UI-DESIGN.md`](docs/UI-DESIGN.md) — colors, typography, layout, motion
- [`docs/BUILD-PLAN.md`](docs/BUILD-PLAN.md) — phased plan, empty repo → v1

## Develop

Requires Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
The Xcode project is generated from `project.yml` (the source of truth) and is git-ignored.

```sh
make project   # generate md-fire.xcodeproj from project.yml
make build     # build from CLI
make run       # build and launch
make open      # open in Xcode
```
