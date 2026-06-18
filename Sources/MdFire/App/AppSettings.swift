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

    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
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
