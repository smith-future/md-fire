import SwiftUI
import AppKit
import Observation

/// App-wide preferences and live system-accessibility state. Single source of truth shared by the
/// SwiftUI layer (RootView) and the AppKit editor Coordinator so both read the same flags.
///
/// `reduceMotion` mirrors macOS System Settings ▸ Accessibility ▸ Display ▸ "Reduce motion" and
/// updates live: the workspace notification center (NOT `NotificationCenter.default`) is the only
/// place the accessibility-options change is posted.
@Observable
final class AppSettings {
    /// True when the user has asked the system to minimize motion. Drives motion gating everywhere.
    var reduceMotion: Bool

    /// Reading speed for the status-bar "min read" estimate (words ÷ wpm).
    let readingWPM = 200

    // MARK: Cockpit preferences (persisted to UserDefaults — one home for every feature's toggle)

    /// F1: auto-reload the open document when it changes on disk (an agent rewrote it).
    var autoReload: Bool { didSet { Self.defaults.set(autoReload, forKey: Keys.autoReload) } }
    /// F1: tint the lines that changed on the last external reload.
    var showChanges: Bool { didSet { Self.defaults.set(showChanges, forKey: Keys.showChanges) } }
    /// F5: keep the window floating above other apps (read the plan while you code in Cursor).
    var alwaysOnTop: Bool { didSet { Self.defaults.set(alwaysOnTop, forKey: Keys.alwaysOnTop) } }
    /// F5: pin special files (CLAUDE.md, ROADMAP.md, *-SPEC.md, .planning/) atop the sidebar.
    var pinSpecialFiles: Bool { didSet { Self.defaults.set(pinSpecialFiles, forKey: Keys.pinSpecialFiles) } }
    /// F3: show the rendered preview pane (tables / Mermaid / code / math) beside the editor.
    var previewVisible: Bool { didSet { Self.defaults.set(previewVisible, forKey: Keys.previewVisible) } }
    /// F5: two-document split view (PLAN beside ARCHITECTURE).
    var splitView: Bool { didSet { Self.defaults.set(splitView, forKey: Keys.splitView) } }

    private static let defaults = UserDefaults.standard
    private enum Keys {
        static let autoReload = "cockpit.autoReload"
        static let showChanges = "cockpit.showChanges"
        static let alwaysOnTop = "cockpit.alwaysOnTop"
        static let pinSpecialFiles = "cockpit.pinSpecialFiles"
        static let previewVisible = "cockpit.previewVisible"
        static let splitView = "cockpit.splitView"
    }

    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        Self.defaults.register(defaults: [
            Keys.autoReload: true,
            Keys.showChanges: true,
            Keys.pinSpecialFiles: true,
        ])
        autoReload = Self.defaults.bool(forKey: Keys.autoReload)
        showChanges = Self.defaults.bool(forKey: Keys.showChanges)
        alwaysOnTop = Self.defaults.bool(forKey: Keys.alwaysOnTop)
        pinSpecialFiles = Self.defaults.bool(forKey: Keys.pinSpecialFiles)
        previewVisible = Self.defaults.bool(forKey: Keys.previewVisible)
        splitView = Self.defaults.bool(forKey: Keys.splitView)

        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    /// The fade animation for the status bar — nil under Reduce Motion so the change snaps instead.
    var statusFadeAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.35)
    }
}
