import SwiftUI
import AppKit

@main
struct SnapKeepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(delegate.app)
                .onAppear { delegate.app.refreshAuthorization() }
        } label: {
            Image(systemName: "camera.viewfinder")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns app-launch wiring: registers global hotkeys and primes Screen Recording permission
/// as soon as the process is up (not just when the menu is first opened).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let app = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.installGlobalHotkeys()
        app.primePermissionOnLaunch()
    }
}
