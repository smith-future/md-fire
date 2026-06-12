import SwiftUI

/// md-fire — a native macOS markdown editor fusing Typora's live WYSIWYG with
/// iA Writer's focus + typography.
///
/// See docs/PRODUCT.md, docs/ARCHITECTURE.md, docs/UI-DESIGN.md, docs/BUILD-PLAN.md.
@main
struct MdFireApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 640, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)               // UI-DESIGN §4.1: chromeless
        .defaultSize(width: 1000, height: 720)      // UI-DESIGN §4.1: default window
    }
}
