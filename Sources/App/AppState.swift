import SwiftUI
import AppKit

/// Central app orchestrator. Owns permission state and drives capture actions from the menu.
@MainActor
@Observable
final class AppState {
    var isAuthorized: Bool = ScreenPermissions.isAuthorized
    var lastSavedURL: URL?
    var statusMessage: String?

    private let regionController = RegionCaptureController()

    func refreshAuthorization() {
        isAuthorized = ScreenPermissions.isAuthorized
    }

    func requestPermission() {
        ScreenPermissions.request()
        // The grant only applies after relaunch; nudge the user toward Settings meanwhile.
        ScreenPermissions.openSystemSettings()
    }

    /// M0 action: capture the whole display, copy to clipboard, and save to ~/Pictures/SnapKeep.
    func captureFullScreen() {
        Task {
            do {
                let image = try await CaptureEngine.shared.captureDisplay()
                CaptureStore.copyToClipboard(image)
                let url = try CaptureStore.savePNG(image)
                lastSavedURL = url
                flash("Saved & copied ✓")
            } catch {
                flash(error.localizedDescription)
            }
        }
    }

    /// M1 action: freeze the screen, let the user drag a region, then copy + save it.
    func captureRegion() {
        Task {
            guard let image = await regionController.begin() else { return } // cancelled
            CaptureStore.copyToClipboard(image)
            do {
                let url = try CaptureStore.savePNG(image)
                lastSavedURL = url
                flash("Saved & copied ✓")
            } catch {
                flash(error.localizedDescription)
            }
        }
    }

    func revealLastInFinder() {
        guard let url = lastSavedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func flash(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if statusMessage == message { statusMessage = nil }
        }
    }
}
