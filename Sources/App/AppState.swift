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
    private let hotKeys = HotKeyManager()
    private var editor: EditorWindowController?

    /// Register the system-wide capture hotkeys. Call once at launch.
    func installGlobalHotkeys() {
        hotKeys.register(
            region: { [weak self] in self?.captureRegion() },
            fullScreen: { [weak self] in self?.captureFullScreen() }
        )
    }

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
                flash("Saved and copied")
            } catch {
                flash(error.localizedDescription)
            }
        }
    }

    /// M1/M2 action: freeze the screen, let the user drag a region, then open the annotation
    /// editor where they can mark it up and copy or save.
    func captureRegion() {
        Task {
            guard let capture = await regionController.begin() else { return } // cancelled
            let controller = EditorWindowController()
            editor = controller
            controller.present(cgImage: capture.cgImage, scale: capture.scale) { [weak self] result in
                switch result {
                case .saved(let url):
                    self?.lastSavedURL = url
                    self?.flash("Saved and copied")
                case .copied:
                    self?.flash("Copied")
                case .closed:
                    break
                }
                self?.editor = nil
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
