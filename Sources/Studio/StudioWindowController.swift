import SwiftUI
import AVKit
import AVFoundation

/// Post-recording editor: preview, trim, and export. The first piece of the Recording Studio;
/// music/captions/overlays/silence-removal layer on top of this.
@MainActor
final class StudioWindowController {
    private var window: NSWindow?
    var onClose: ((StudioWindowController) -> Void)?

    /// `onExport` receives the finished (trimmed) file, or nil if the user cancelled.
    func present(videoURL: URL, onExport: @escaping (URL?) -> Void) {
        let model = StudioModel(url: videoURL)
        let root = StudioView(model: model,
                              onExport: { [weak self] url in self?.close(); onExport(url) },
                              onCancel: { [weak self] in self?.close(); onExport(nil) })
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 720, height: 620),
                           styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.title = "\(Brand.name) — Studio"
        win.titlebarAppearsTransparent = true
        win.contentView = NSHostingView(rootView: root)
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
        onClose?(self)
    }
}

// MARK: - Model

@MainActor
@Observable
final class StudioModel {
    let url: URL
    let player: AVPlayer
    var duration: Double = 0
    var trimStart: Double = 0
    var trimEnd: Double = 0
    var current: Double = 0
    var exporting = false

    private var timeObserver: Any?

    init(url: URL) {
        self.url = url
        self.player = AVPlayer(url: url)
    }

    func load() async {
        let asset = AVURLAsset(url: url)
        let dur = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        duration = dur
        trimEnd = dur
        // Follow playback for the playhead + loop within the trim range.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.03, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.current = CMTimeGetSeconds(t)
                if self.current >= self.trimEnd { self.seek(to: self.trimStart) }
            }
        }
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        current = seconds
    }

    /// Export the trimmed range to a new MP4. Returns the temp URL, or nil on failure.
    func export() async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
        else { return nil }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("studio-\(UUID().uuidString).mp4")
        session.outputURL = out
        session.outputFileType = .mp4
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            end: CMTime(seconds: max(trimEnd, trimStart + 0.1), preferredTimescale: 600))

        return await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            session.exportAsynchronously {
                cont.resume(returning: session.status == .completed ? out : nil)
            }
        }
    }
}

// MARK: - View

private struct StudioView: View {
    @Bindable var model: StudioModel
    let onExport: (URL?) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            VideoPlayer(player: model.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))

            TrimBar(model: model)

            HStack {
                Text("\(timeString(model.trimStart)) – \(timeString(model.trimEnd))")
                    .font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { onCancel() }
                Button {
                    Task {
                        model.exporting = true
                        let url = await model.export()
                        model.exporting = false
                        onExport(url)
                    }
                } label: {
                    if model.exporting { ProgressView().controlSize(.small) }
                    else { Text("Export") }
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(model.exporting)
            }
        }
        .padding(Theme.Space.lg)
        .frame(minWidth: 560, minHeight: 480)
        .task { await model.load() }
        .onExitCommand { onCancel() }
    }

    private func timeString(_ s: Double) -> String {
        String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
}

/// A timeline with draggable in/out handles and a playhead.
private struct TrimBar: View {
    @Bindable var model: StudioModel

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let dur = max(model.duration, 0.1)
            let x = { (t: Double) in CGFloat(t / dur) * w }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(height: 46)

                // Selected range.
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.accent.opacity(0.22))
                    .frame(width: max(0, x(model.trimEnd) - x(model.trimStart)), height: 46)
                    .offset(x: x(model.trimStart))
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.accent, lineWidth: 2)
                    .frame(width: max(0, x(model.trimEnd) - x(model.trimStart)), height: 46)
                    .offset(x: x(model.trimStart))

                // Playhead.
                Rectangle().fill(.white).frame(width: 2, height: 46).offset(x: x(model.current))

                // Handles.
                handle.offset(x: x(model.trimStart) - 6)
                    .gesture(drag(in: w, dur: dur) {
                        model.trimStart = clamp($0, 0, model.trimEnd - 0.2, dur); model.seek(to: model.trimStart)
                    })
                handle.offset(x: x(model.trimEnd) - 6)
                    .gesture(drag(in: w, dur: dur) {
                        model.trimEnd = clamp($0, model.trimStart + 0.2, dur, dur)
                    })
            }
        }
        .frame(height: 46)
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 4).fill(Theme.accent)
            .frame(width: 12, height: 52)
            .overlay(Rectangle().fill(.white.opacity(0.9)).frame(width: 2, height: 20))
    }

    private func drag(in width: CGFloat, dur: Double, _ update: @escaping (Double) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { v in
            update(Double(v.location.x / width) * dur)
        }
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double, _ dur: Double) -> Double {
        min(max(v, max(0, lo)), min(hi, dur))
    }
}
