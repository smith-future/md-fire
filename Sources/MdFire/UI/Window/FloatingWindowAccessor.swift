import SwiftUI
import AppKit

/// Sets the host window's level so md-fire floats above other apps — the plan stays beside you while
/// you code in Cursor (F5). The SwiftUI scene exposes no NSWindow, so this tiny representable walks up
/// to `view.window` and sets `.floating` / `.normal` + all-spaces behaviour from the bound flag.
struct FloatingWindowAccessor: NSViewRepresentable {
    let floating: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window else { return }
        window.level = floating ? .floating : .normal
        if floating {
            window.collectionBehavior.insert(.canJoinAllSpaces)
        } else {
            window.collectionBehavior.remove(.canJoinAllSpaces)
        }
    }
}
