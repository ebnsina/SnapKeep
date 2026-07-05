import SwiftUI
import AVKit
import AVFoundation
import UniformTypeIdentifiers

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
    private(set) var url: URL
    let player: AVPlayer
    var duration: Double = 0
    var trimStart: Double = 0
    var trimEnd: Double = 0
    var current: Double = 0
    var exporting = false

    var musicURL: URL?
    var musicVolume: Double = 0.6

    var captions: [Caption] = []
    var captionsEnabled = false
    var generatingCaptions = false

    var processingSilence = false

    /// The caption line active at the current playhead (for live preview).
    var currentCaption: String? {
        guard captionsEnabled else { return nil }
        return captions.first { current >= $0.start && current <= $0.end }?.text
    }

    private var timeObserver: Any?

    init(url: URL) {
        self.url = url
        self.player = AVPlayer(url: url)
    }

    func load() async {
        let asset = AVURLAsset(url: url)
        let dur = (try? await asset.load(.duration)).map { CMTimeGetSeconds($0) } ?? 0
        duration = dur
        trimStart = 0
        trimEnd = dur
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
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

    // MARK: Music

    func setMusic(_ newURL: URL?) {
        musicURL = newURL
        Task { await rebuildPlayerItem() }
    }

    func setVolume(_ v: Double) {
        musicVolume = v
        Task { if let (_, mix) = await buildComposition() { player.currentItem?.audioMix = mix } }
    }

    private func rebuildPlayerItem() async {
        guard musicURL != nil, let (comp, mix) = await buildComposition() else {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            seek(to: trimStart); return
        }
        let item = AVPlayerItem(asset: comp)
        item.audioMix = mix
        player.replaceCurrentItem(with: item)
        seek(to: trimStart)
    }

    /// Build a composition with the video, its audio, and (if set) looped background music.
    private func buildComposition() async -> (AVMutableComposition, AVMutableAudioMix?)? {
        let comp = AVMutableComposition()
        let video = AVURLAsset(url: url)
        do {
            let dur = try await video.load(.duration)
            let range = CMTimeRange(start: .zero, duration: dur)
            if let v = try await video.loadTracks(withMediaType: .video).first,
               let track = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try track.insertTimeRange(range, of: v, at: .zero)
                track.preferredTransform = try await v.load(.preferredTransform)
            }
            if let a = try await video.loadTracks(withMediaType: .audio).first,
               let track = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try track.insertTimeRange(range, of: a, at: .zero)
            }

            var mix: AVMutableAudioMix?
            if let musicURL {
                let music = AVURLAsset(url: musicURL)
                if let m = try await music.loadTracks(withMediaType: .audio).first,
                   let track = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                    let mDur = try await music.load(.duration)
                    var at = CMTime.zero
                    while at < dur, mDur.seconds > 0.1 {
                        let chunk = min(dur - at, mDur)
                        try track.insertTimeRange(CMTimeRange(start: .zero, duration: chunk), of: m, at: at)
                        at = at + chunk
                    }
                    let params = AVMutableAudioMixInputParameters(track: track)
                    params.setVolume(Float(musicVolume), at: .zero)
                    let m2 = AVMutableAudioMix(); m2.inputParameters = [params]; mix = m2
                }
            }
            return (comp, mix)
        } catch {
            return nil
        }
    }

    // MARK: Captions

    func generateCaptions() async {
        generatingCaptions = true
        let caps = await CaptionTranscriber.transcribe(url: url)
        captions = caps
        captionsEnabled = !caps.isEmpty
        generatingCaptions = false
    }

    /// A video composition that burns the caption lines in as timed overlays.
    private func makeCaptionComposition(for asset: AVAsset) async -> AVMutableVideoComposition? {
        guard captionsEnabled, !captions.isEmpty,
              let track = try? await asset.loadTracks(withMediaType: .video).first else { return nil }
        let natural = (try? await track.load(.naturalSize)) ?? CGSize(width: 1280, height: 720)
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let r = natural.applying(transform)
        let size = CGSize(width: abs(r.width) > 0 ? abs(r.width) : natural.width,
                          height: abs(r.height) > 0 ? abs(r.height) : natural.height)
        let total = max(duration, 0.1)

        let vc = AVMutableVideoComposition(propertiesOf: asset)
        vc.renderSize = size

        let parent = CALayer(); parent.frame = CGRect(origin: .zero, size: size)
        let videoLayer = CALayer(); videoLayer.frame = parent.frame
        let overlay = CALayer(); overlay.frame = parent.frame
        parent.addSublayer(videoLayer); parent.addSublayer(overlay)

        let fontSize = size.height * 0.05
        for cap in captions {
            let text = CATextLayer()
            text.string = cap.text
            text.font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, fontSize, nil)
            text.fontSize = fontSize
            text.alignmentMode = .center
            text.foregroundColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            text.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            text.shadowOpacity = 1; text.shadowRadius = 4; text.shadowOffset = .zero
            text.isWrapped = true
            text.contentsScale = 2
            text.frame = CGRect(x: size.width * 0.08, y: size.height * 0.07,
                                width: size.width * 0.84, height: fontSize * 2.4)
            text.opacity = 0

            let anim = CAKeyframeAnimation(keyPath: "opacity")
            let s = min(max(cap.start / total, 0), 1)
            let e = min(max(cap.end / total, s + 0.0001), 1)
            anim.values = [0, 0, 1, 1, 0, 0]
            anim.keyTimes = [0, s, s, e, e, 1] as [NSNumber]
            anim.duration = total
            anim.beginTime = AVCoreAnimationBeginTimeAtZero
            anim.isRemovedOnCompletion = false
            anim.fillMode = .both
            text.add(anim, forKey: "opacity")
            overlay.addSublayer(text)
        }
        vc.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
        return vc
    }

    // MARK: Remove silences

    /// Detect silent gaps, rebuild the video without them, and reload the Studio on the result.
    /// This "bakes" the cut, so it's best done before captions (timestamps shift).
    func removeSilences() async {
        processingSilence = true
        defer { processingSilence = false }

        let ranges = await SilenceDetector.loudRanges(url: url)
        guard ranges.count > 1 else { return } // nothing meaningful to cut

        let comp = AVMutableComposition()
        let asset = AVURLAsset(url: url)
        guard let v = try? await asset.loadTracks(withMediaType: .video).first,
              let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return }
        vTrack.preferredTransform = (try? await v.load(.preferredTransform)) ?? .identity
        let a = try? await asset.loadTracks(withMediaType: .audio).first
        let aTrack = a != nil ? comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) : nil

        var at = CMTime.zero
        for r in ranges {
            try? vTrack.insertTimeRange(r, of: v, at: at)
            if let a, let aTrack { try? aTrack.insertTimeRange(r, of: a, at: at) }
            at = at + r.duration
        }

        guard let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)
        else { return }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("desilenced-\(UUID().uuidString).mp4")
        session.outputURL = out
        session.outputFileType = .mp4
        let done: Bool = await withCheckedContinuation { cont in
            session.exportAsynchronously { cont.resume(returning: session.status == .completed) }
        }
        guard done else { return }

        // Swap in the cleaned file; captions no longer line up, so clear them.
        url = out
        captions = []; captionsEnabled = false
        player.replaceCurrentItem(with: AVPlayerItem(url: out))
        await load()
        if musicURL != nil { await rebuildPlayerItem() }
    }

    // MARK: Export

    /// Export the trimmed range (with music + captions if set) to a new MP4. Nil on failure.
    func export() async -> URL? {
        let asset: AVAsset
        let mix: AVAudioMix?
        if musicURL != nil, let built = await buildComposition() {
            asset = built.0; mix = built.1
        } else {
            asset = AVURLAsset(url: url); mix = nil
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
        else { return nil }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("studio-\(UUID().uuidString).mp4")
        session.outputURL = out
        session.outputFileType = .mp4
        session.audioMix = mix
        session.videoComposition = await makeCaptionComposition(for: asset)
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
                .overlay(alignment: .bottom) {
                    if let caption = model.currentCaption {
                        Text(caption)
                            .font(.system(size: 16, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                            .padding(.bottom, 18).padding(.horizontal, 24)
                            .shadow(radius: 4)
                    }
                }

            TrimBar(model: model)

            musicRow
            captionsRow
            silenceRow

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

    @ViewBuilder private var musicRow: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "music.note").foregroundStyle(.secondary)
            if let m = model.musicURL {
                Text(m.deletingPathExtension().lastPathComponent)
                    .font(.callout).lineLimit(1).truncationMode(.middle)
                Image(systemName: "speaker.wave.2").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(get: { model.musicVolume }, set: { model.setVolume($0) }), in: 0...1)
                    .controlSize(.small).frame(width: 90).tint(Theme.accent)
                Button { model.setMusic(nil) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
            } else {
                Text("Add background music").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Choose Audio…") { chooseMusic() }
            }
            if model.musicURL != nil { Spacer() }
        }
        .padding(Theme.Space.sm)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    @ViewBuilder private var captionsRow: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "captions.bubble").foregroundStyle(.secondary)
            if model.generatingCaptions {
                Text("Transcribing on-device…").font(.callout).foregroundStyle(.secondary)
                Spacer(); ProgressView().controlSize(.small)
            } else if model.captions.isEmpty {
                Text("Auto-generate captions").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Generate") { Task { await model.generateCaptions() } }
            } else {
                Text("\(model.captions.count) caption lines").font(.callout)
                Spacer()
                Toggle("Show", isOn: $model.captionsEnabled).toggleStyle(.switch).controlSize(.mini)
                Button("Regenerate") { Task { await model.generateCaptions() } }
            }
        }
        .padding(Theme.Space.sm)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    @ViewBuilder private var silenceRow: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "waveform.path").foregroundStyle(.secondary)
            if model.processingSilence {
                Text("Removing silent gaps…").font(.callout).foregroundStyle(.secondary)
                Spacer(); ProgressView().controlSize(.small)
            } else {
                Text("Cut out silent gaps").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Remove Silences") { Task { await model.removeSilences() } }
            }
        }
        .padding(Theme.Space.sm)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    private func chooseMusic() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio, .mp3, .wav, .mpeg4Audio]
        if panel.runModal() == .OK, let url = panel.url { model.setMusic(url) }
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
