import SwiftUI
import AppKit

/// Orchestrates a screen recording: starts the engine, shows a floating control bar with a
/// live timer + Stop button, and on stop saves the result (MP4 or converted GIF).
@MainActor
@Observable
final class RecordingController {
    private(set) var isRecording = false
    private(set) var elapsed: Int = 0

    private let engine = RecordingEngine()
    private var controlWindow: NSWindow?
    private var timer: Timer?
    private var onFinished: ((URL?) -> Void)?

    var isBusy = false // converting/finalizing

    /// Toggle full-screen recording of the display under the cursor.
    func toggle(onFinished: @escaping (URL?) -> Void) {
        if isRecording { stop(); return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let displayID = (screen?.deviceDescription[.init("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
        let scale = Int(screen?.backingScaleFactor ?? 2)
        start(displayID: displayID, scale: scale, sourceRect: nil, onFinished: onFinished)
    }

    /// Start recording just a selected region (points, top-left origin within the display).
    func startRegion(displayID: CGDirectDisplayID, scale: Int, sourceRect: CGRect,
                     onFinished: @escaping (URL?) -> Void) {
        start(displayID: displayID, scale: scale, sourceRect: sourceRect, onFinished: onFinished)
    }

    private func start(displayID: CGDirectDisplayID, scale: Int, sourceRect: CGRect?,
                       onFinished: @escaping (URL?) -> Void) {
        guard !isRecording else { return }
        self.onFinished = onFinished
        let fps = AppSettings.shared.recordFPS
        let audio = AppSettings.shared.recordSystemAudio
        Task {
            do {
                try await engine.start(displayID: displayID, scale: scale, fps: fps,
                                       captureAudio: audio, sourceRect: sourceRect)
                isRecording = true
                elapsed = 0
                showControlBar()
                startTimer()
            } catch {
                onFinished(nil)
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        isBusy = true
        stopTimer()
        hideControlBar()

        engine.stop { [weak self] url in
            guard let self else { return }
            guard let url else { self.isBusy = false; self.onFinished?(nil); return }
            Task { await self.finalize(tempURL: url) }
        }
    }

    /// Produce the final-format file in a temp location and hand it back. The caller decides
    /// whether/where to save it (no auto-save).
    private func finalize(tempURL: URL) async {
        var finalURL: URL?
        if AppSettings.shared.recordFormat == .gif {
            let gifURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(CaptureStore.suggestedName(ext: "gif"))
            if await GIFExporter.convert(videoURL: tempURL, to: gifURL) {
                finalURL = gifURL
            }
            try? FileManager.default.removeItem(at: tempURL)
        } else {
            finalURL = tempURL // already an mp4 in the temp dir
        }

        isBusy = false
        onFinished?(finalURL)
        onFinished = nil
    }

    // MARK: Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed += 1 }
        }
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }

    // MARK: Control bar

    private func showControlBar() {
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 190, height: 44),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .statusBar
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        win.contentView = NSHostingView(rootView: RecordingBar(controller: self) { [weak self] in self?.stop() })

        if let screen = NSScreen.main {
            // Sit just below the menu bar (visibleFrame excludes it), clear of the notch.
            let x = screen.frame.midX - 95
            let y = screen.visibleFrame.maxY - 44 - 10
            win.setFrameOrigin(CGPoint(x: x, y: y))
        }
        win.orderFrontRegardless()
        controlWindow = win
    }

    private func hideControlBar() {
        controlWindow?.orderOut(nil)
        controlWindow = nil
    }
}

/// The floating recording control bar.
private struct RecordingBar: View {
    @Bindable var controller: RecordingController
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Circle().fill(.red).frame(width: 10, height: 10)
                .opacity(0.9)
            Text(timeString).font(.system(.body, design: .monospaced).weight(.medium))
                .foregroundStyle(.white)
            Spacer()
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.red, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Stop recording")
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .background(.black.opacity(0.8), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
    }

    private var timeString: String {
        String(format: "%02d:%02d", controller.elapsed / 60, controller.elapsed % 60)
    }
}
