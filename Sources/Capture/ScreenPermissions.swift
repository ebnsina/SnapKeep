import CoreGraphics
import AppKit

/// Thin wrapper around the Screen Recording TCC permission that ScreenCaptureKit requires.
enum ScreenPermissions {
    /// True if the app already has Screen Recording permission (no prompt shown).
    static var isAuthorized: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Ask the system for Screen Recording access. The first call surfaces the TCC prompt;
    /// afterwards macOS requires the app to be relaunched for the grant to take effect.
    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Deep-link the user straight to the Screen Recording pane in System Settings.
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
