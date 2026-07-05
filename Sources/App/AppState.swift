import SwiftUI
import AppKit

/// Central app orchestrator. Owns permission state and drives capture actions from the menu.
@MainActor
@Observable
final class AppState {
    var isAuthorized: Bool = ScreenPermissions.isAuthorized
    var lastSavedURL: URL?
    var statusMessage: String?

    let library = CaptureLibrary()

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

    /// Called once at launch: touch ScreenCaptureKit so macOS shows its native prompt and
    /// binds the grant to this binary, then refresh the UI.
    func primePermissionOnLaunch() {
        Task {
            await CaptureEngine.shared.primePermission()
            refreshAuthorization()
        }
    }

    /// Grant Access button: drive ScreenCaptureKit's own prompt (reliable), falling back to
    /// the legacy request API, then refresh.
    func requestPermission() {
        Task {
            let ok = await CaptureEngine.shared.primePermission()
            if !ok { ScreenPermissions.request() }
            refreshAuthorization()
        }
    }

    func openScreenRecordingSettings() {
        ScreenPermissions.openSystemSettings()
    }

    /// Screen Recording permission only reaches a *freshly launched* process, so after the
    /// user grants it we relaunch a new instance and quit this one.
    func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            NSApp.terminate(nil)
        }
    }

    /// M0 action: capture the whole display, copy to clipboard, and save to ~/Pictures/SnapKeep.
    func captureFullScreen() {
        Task {
            do {
                let image = try await CaptureEngine.shared.captureDisplay()
                CaptureStore.copyToClipboard(image)
                let url = try CaptureStore.savePNG(image)
                lastSavedURL = url
                library.register(url)
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
                    self?.library.register(url)
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

    /// Copy a saved capture's image back onto the clipboard.
    func copyToClipboard(_ item: CaptureItem) {
        guard let image = NSImage(contentsOf: item.url) else { return }
        CaptureStore.copyToClipboard(image)
        flash("Copied")
    }

    func reveal(_ item: CaptureItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    private func flash(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if statusMessage == message { statusMessage = nil }
        }
    }
}
