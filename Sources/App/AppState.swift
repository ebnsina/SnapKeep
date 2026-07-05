import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    private let regionSelector = RegionSelectorController()
    private let scrollController = ScrollCaptureController()
    let recorder = RecordingController()
    private let hotKeys = HotKeyManager()
    private var editor: EditorWindowController?
    private var settingsWindow: SettingsWindowController?
    private var onboarding: OnboardingWindowController?
    private var studio: StudioWindowController?
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
            record: { [weak self] in self?.toggleRecording() },
            palette: { [weak self] in self?.togglePalette() }
        )
    }

    /// Start or stop a screen recording (MP4 or GIF per settings). On stop, prompt the user
    /// to save (with a rename) rather than auto-saving.
    func toggleRecording() {
        // The floating control bar is the recording indicator, so no start HUD (it would
        // overlap the bar). The HUD is used only for the saved/failed result.
        recorder.toggle { [weak self] tempURL in
            guard let self else { return }
            guard let tempURL else { self.flash("Recording failed"); return }
            self.openStudio(tempURL: tempURL)
        }
    }

    /// Scrolling capture: pick a viewport, scroll, and stitch into one tall image.
    func scrollingCapture() {
        Task {
            guard let region = await regionSelector.begin() else { return } // cancelled
            scrollController.begin(region: region) { [weak self] composed, scale in
                guard let self else { return }
                guard let composed else { self.flash("Scrolling capture cancelled"); return }
                self.openEditor(cgImage: composed, scale: scale)
            }
        }
    }

    /// Record just a selected region. Toggles off if already recording.
    func recordRegion() {
        if recorder.isRecording { recorder.stop(); return }
        Task {
            guard let sel = await regionSelector.begin() else { return } // cancelled
            recorder.startRegion(displayID: sel.displayID, scale: sel.scale, sourceRect: sel.sourceRect) { [weak self] tempURL in
                guard let self else { return }
                guard let tempURL else { self.flash("Recording failed"); return }
                self.openStudio(tempURL: tempURL)
            }
        }
    }

    /// Open the Recording Studio (trim/export) for a finished video. GIFs skip straight to
    /// the save prompt since the studio is video-only for now.
    private func openStudio(tempURL: URL) {
        if tempURL.pathExtension.lowercased() == "gif" { promptSaveRecording(tempURL: tempURL); return }
        let controller = StudioWindowController()
        studio = controller
        controller.onClose = { [weak self] _ in self?.studio = nil }
        controller.present(videoURL: tempURL) { [weak self] exported in
            guard let self else { return }
            try? FileManager.default.removeItem(at: tempURL) // discard the raw recording
            if let exported {
                self.promptSaveRecording(tempURL: exported)
            } else {
                self.flash("Recording discarded")
            }
        }
    }

    /// Ask where/what to save the finished recording; discard the temp file if cancelled.
    private func promptSaveRecording(tempURL: URL) {
        let ext = tempURL.pathExtension
        let panel = NSSavePanel()
        panel.title = "Save Recording"
        panel.nameFieldStringValue = CaptureStore.suggestedName(ext: ext)
        panel.directoryURL = AppSettings.shared.saveDirectory
        panel.canCreateDirectories = true
        if let type = UTType(filenameExtension: ext) { panel.allowedContentTypes = [type] }

        NSApp.activate(ignoringOtherApps: true) // agent app: bring the panel to front
        let response = panel.runModal()
        guard response == .OK, let dest = panel.url else {
            try? FileManager.default.removeItem(at: tempURL)
            flash("Recording discarded")
            return
        }
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)
            library.register(dest)
            lastSavedURL = dest
            flash("Recording saved")
            NotchHUDController.shared.show(icon: "record.circle.fill", title: "Recording saved",
                                           subtitle: dest.lastPathComponent,
                                           thumbnail: library.thumbnail(for: CaptureItem(id: dest, date: Date())),
                                           tint: .red)
        } catch {
            flash(error.localizedDescription)
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
        let controller = settingsWindow ?? SettingsWindowController(app: self)
        settingsWindow = controller
        controller.show()
    }

    /// Re-register global hotkeys after the user changes a binding.
    func reloadHotkeys() { hotKeys.reload() }

    /// Open (or close) the ⌘K command palette with all actions + recent captures.
    func togglePalette() {
        func key(_ a: HotKeyAction) -> String { AppSettings.shared.binding(for: a).display }
        var commands: [Command] = [
            Command(title: "Capture Region", subtitle: key(.region), symbol: "rectangle.dashed") { [weak self] in self?.captureRegion() },
            Command(title: "Capture Window", subtitle: key(.window), symbol: "macwindow") { [weak self] in self?.captureWindow() },
            Command(title: "Capture Full Screen", subtitle: key(.fullScreen), symbol: "rectangle.inset.filled") { [weak self] in self?.captureFullScreen() },
            Command(title: "Scrolling Capture", subtitle: nil, symbol: "arrow.down.doc") { [weak self] in self?.scrollingCapture() },
            Command(title: "Recapture Last Region", subtitle: key(.lastRegion), symbol: "arrow.clockwise") { [weak self] in self?.recaptureLastRegion() },
            Command(title: recorder.isRecording ? "Stop Recording" : "Record Screen", subtitle: key(.record),
                    symbol: recorder.isRecording ? "stop.circle.fill" : "record.circle") { [weak self] in self?.toggleRecording() },
            Command(title: "Record Region", subtitle: nil, symbol: "rectangle.dashed.badge.record") { [weak self] in self?.recordRegion() },
            Command(title: "Settings…", subtitle: nil, symbol: "gearshape") { [weak self] in self?.openSettings() },
            Command(title: "Show Welcome", subtitle: nil, symbol: "sparkles") { [weak self] in self?.showOnboarding() }
        ]
        for item in library.items.prefix(5) {
            commands.append(Command(title: "Copy “\(item.displayName)”", subtitle: item.ext, symbol: "doc.on.doc") {
                [weak self] in self?.copyToClipboard(item)
            })
        }
        CommandPaletteController.shared.toggle(commands: commands)
    }

    func showOnboarding() {
        let controller = onboarding ?? OnboardingWindowController(app: self)
        onboarding = controller
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
