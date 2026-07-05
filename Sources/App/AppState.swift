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
    private let windowController = WindowCaptureController()
    let recorder = RecordingController()
    private let hotKeys = HotKeyManager()
    private var editor: EditorWindowController?
    private var settingsWindow: SettingsWindowController?
    private var pins: [PinWindowController] = []

    /// Remembers the last region so it can be recaptured with one shortcut.
    private var lastRegion: (displayID: CGDirectDisplayID, rect: CGRect, scale: CGFloat)?

    /// Register the system-wide capture hotkeys. Call once at launch.
    func installGlobalHotkeys() {
        hotKeys.register(
            region: { [weak self] in self?.captureRegion() },
            fullScreen: { [weak self] in self?.captureFullScreen() },
            window: { [weak self] in self?.captureWindow() },
            lastRegion: { [weak self] in self?.recaptureLastRegion() },
            record: { [weak self] in self?.toggleRecording() }
        )
    }

    /// Start or stop a screen recording (MP4 or GIF per settings).
    func toggleRecording() {
        let starting = !recorder.isRecording
        recorder.toggle { [weak self] url in
            guard let self else { return }
            if let url {
                self.library.register(url)
                self.lastSavedURL = url
                self.flash("Recording saved")
                NotchHUDController.shared.show(icon: "record.circle.fill", title: "Recording saved",
                                               subtitle: url.lastPathComponent,
                                               thumbnail: self.library.thumbnail(for: CaptureItem(id: url, date: Date())),
                                               tint: .red)
            } else {
                self.flash("Recording failed")
            }
        }
        if starting {
            NotchHUDController.shared.show(icon: "record.circle.fill", title: "Recording…",
                                           subtitle: "⌘⇧6 to stop", tint: .red)
        }
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

    /// Run a capture after the user's configured delay (0 = immediate).
    private func withDelay(_ action: @escaping () async -> Void) {
        let delay = AppSettings.shared.captureDelay
        Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            await action()
        }
    }

    /// Capture the whole display, then copy (if enabled) and save per settings.
    func captureFullScreen() {
        withDelay { [weak self] in
            guard let self else { return }
            do {
                let image = try await CaptureEngine.shared.captureDisplay()
                self.quickSave(image)
            } catch {
                self.flash(error.localizedDescription)
            }
        }
    }

    /// Freeze the screen, let the user drag a region, then open the annotation editor.
    func captureRegion() {
        withDelay { [weak self] in
            guard let self else { return }
            guard let capture = await self.regionController.begin() else { return } // cancelled
            self.lastRegion = (capture.displayID, capture.pixelRect, capture.scale)
            self.openEditor(cgImage: capture.cgImage, scale: capture.scale)
        }
    }

    /// Hover to highlight a window, click to capture it, then open the editor.
    func captureWindow() {
        withDelay { [weak self] in
            guard let self else { return }
            guard let capture = await self.windowController.begin() else { return }
            self.openEditor(cgImage: capture.cgImage, scale: capture.scale)
        }
    }

    /// Recapture the exact region from the last region capture without reselecting.
    func recaptureLastRegion() {
        guard let last = lastRegion else { flash("No previous region yet"); return }
        withDelay { [weak self] in
            guard let self else { return }
            do {
                let full = try await CaptureEngine.shared.captureScreenImage(
                    displayID: last.displayID, scale: Int(last.scale))
                guard let cropped = full.cropping(to: last.rect) else { return }
                self.openEditor(cgImage: cropped, scale: last.scale)
            } catch {
                self.flash(error.localizedDescription)
            }
        }
    }

    /// Copy (if enabled) + save a plain capture, updating history.
    private func quickSave(_ image: NSImage) {
        if AppSettings.shared.autoCopy { CaptureStore.copyToClipboard(image) }
        do {
            let url = try CaptureStore.save(image)
            lastSavedURL = url
            library.register(url)
            let copied = AppSettings.shared.autoCopy
            flash(copied ? "Saved and copied" : "Saved")
            NotchHUDController.shared.show(icon: "checkmark.circle.fill",
                                           title: copied ? "Saved and copied" : "Saved",
                                           subtitle: url.lastPathComponent, thumbnail: image)
        } catch {
            flash(error.localizedDescription)
        }
    }

    /// Open the annotation editor for a captured image and route its result.
    private func openEditor(cgImage: CGImage, scale: CGFloat) {
        let controller = EditorWindowController()
        editor = controller
        controller.present(cgImage: cgImage, scale: scale) { [weak self] result in
            switch result {
            case .saved(let url):
                self?.lastSavedURL = url
                self?.library.register(url)
                self?.flash("Saved")
                NotchHUDController.shared.show(icon: "checkmark.circle.fill", title: "Saved",
                                               subtitle: url.lastPathComponent,
                                               thumbnail: NSImage(contentsOf: url))
            case .copied:
                self?.flash("Copied")
                NotchHUDController.shared.show(icon: "doc.on.doc.fill", title: "Copied to clipboard")
            case .closed:
                break
            }
            self?.editor = nil
        }
    }

    // MARK: Settings & pins

    func openSettings() {
        let controller = settingsWindow ?? SettingsWindowController()
        settingsWindow = controller
        controller.show()
    }

    /// Pin a saved capture as a floating always-on-top window.
    func pin(_ item: CaptureItem) {
        guard let image = NSImage(contentsOf: item.url) else { return }
        let controller = PinWindowController(image: image)
        pins.append(controller)
        controller.onClose = { [weak self] c in self?.pins.removeAll { $0 === c } }
        controller.show()
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
        NotchHUDController.shared.show(icon: "doc.on.doc.fill", title: "Copied to clipboard",
                                       thumbnail: image)
    }

    func reveal(_ item: CaptureItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    /// Open a capture in its default app (used for recordings, which aren't clipboard images).
    func open(_ item: CaptureItem) {
        NSWorkspace.shared.open(item.url)
    }

    private func flash(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if statusMessage == message { statusMessage = nil }
        }
    }
}
