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

    var logoURL: URL?
    var logoImage: NSImage?
    var logoPos = CGPoint(x: 0.86, y: 0.12) // normalized center, y from top
    var logoScale: Double = 0.15

    var thumbnails: [NSImage] = []
    var isPlaying = false

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
        await generateThumbnails()
    }

    func togglePlay() {
        if isPlaying {
            player.pause()
        } else {
            if current >= trimEnd - 0.05 { seek(to: trimStart) }
            player.play()
        }
        isPlaying.toggle()
    }

    private func generateThumbnails(count: Int = 14) async {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 220, height: 140)
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.6, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.6, preferredTimescale: 600)
        let dur = max(duration, 0.1)
        let times = (0..<count).map { CMTime(seconds: dur * Double($0) / Double(count), preferredTimescale: 600) }

        var pairs: [(Double, NSImage)] = []
        for await result in gen.images(for: times) {
            if let cg = try? result.image {
                pairs.append((result.requestedTime.seconds, NSImage(cgImage: cg, size: .zero)))
            }
        }
        thumbnails = pairs.sorted { $0.0 < $1.0 }.map { $0.1 }
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

    // MARK: Logo

    func setLogo(_ newURL: URL?) {
        logoURL = newURL
        logoImage = newURL.flatMap { NSImage(contentsOf: $0) }
    }

    // MARK: Captions

    func generateCaptions() async {
        generatingCaptions = true
        let caps = await CaptionTranscriber.transcribe(url: url)
        captions = caps
        captionsEnabled = !caps.isEmpty
        generatingCaptions = false
    }

    /// A video composition that burns in captions (timed) and/or a logo image overlay.
    private func makeOverlayComposition(for asset: AVAsset) async -> AVMutableVideoComposition? {
        let hasCaptions = captionsEnabled && !captions.isEmpty
        let hasLogo = logoImage != nil
        guard hasCaptions || hasLogo,
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

        // Logo image at a free (normalized-center) position.
        if let logoImage, let cg = logoImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let w = size.width * logoScale
            let h = w * (CGFloat(cg.height) / CGFloat(cg.width))
            let cx = size.width * logoPos.x
            let cy = size.height * (1 - logoPos.y) // CALayer origin is bottom-left
            let layer = CALayer()
            layer.frame = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
            layer.contents = cg
            layer.contentsGravity = .resizeAspect
            overlay.addSublayer(layer)
        }

        let fontSize = size.height * 0.05
        for cap in (hasCaptions ? captions : []) {
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
        session.videoComposition = await makeOverlayComposition(for: asset)
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
            PlayerView(player: model.player)
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
                .overlay {
                    if let logo = model.logoImage {
                        GeometryReader { geo in
                            Image(nsImage: logo).resizable().scaledToFit()
                                .frame(width: geo.size.width * model.logoScale)
                                .shadow(color: .black.opacity(0.25), radius: 3)
                                .position(x: geo.size.width * model.logoPos.x,
                                          y: geo.size.height * model.logoPos.y)
                                .gesture(DragGesture().onChanged { v in
                                    model.logoPos = CGPoint(
                                        x: min(max(v.location.x / geo.size.width, 0), 1),
                                        y: min(max(v.location.y / geo.size.height, 0), 1))
                                })
                        }
                    }
                }

            transportRow
            Timeline(model: model)

            musicRow
            captionsRow
            silenceRow
            logoRow

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

    private var transportRow: some View {
        HStack(spacing: Theme.Space.md) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Theme.accent, in: Circle())
                    .foregroundStyle(.white)
            }.buttonStyle(.plain)
            Text(timeString(model.current)).font(.system(.callout, design: .monospaced))
            Spacer()
            Text(timeString(model.duration)).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var logoRow: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "photo.badge.plus").foregroundStyle(.secondary)
            if model.logoImage != nil {
                Text("Logo — drag to move").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.down.left.and.arrow.up.right").font(.caption).foregroundStyle(.secondary)
                Slider(value: $model.logoScale, in: 0.05...0.4).controlSize(.small).frame(width: 110).tint(Theme.accent)
                Button { model.setLogo(nil) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.tertiary)
            } else {
                Text("Add a logo / watermark").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Choose Image…") { chooseLogo() }
            }
        }
        .padding(Theme.Space.sm)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    private func chooseLogo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .png, .jpeg]
        if panel.runModal() == .OK, let url = panel.url { model.setLogo(url) }
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

/// AppKit AVPlayerView wrapper — avoids a Swift-runtime crash instantiating SwiftUI's
/// generic `VideoPlayer` metadata on this OS/toolchain.
private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .inline
        v.videoGravity = .resizeAspect
        return v
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }
}

/// A professional trim timeline: a thumbnail filmstrip, dimmed out-of-range areas, draggable
/// in/out handles, a playhead, and click/drag-to-scrub.
private struct Timeline: View {
    @Bindable var model: StudioModel
    private let height: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let dur = max(model.duration, 0.1)
            let x = { (t: Double) in CGFloat(t / dur) * w }
            let sx = x(model.trimStart), ex = x(model.trimEnd)

            ZStack(alignment: .leading) {
                filmstrip(width: w)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        let t = min(max(Double(v.location.x / w) * dur, 0), dur)
                        model.seek(to: t)
                    })

                // Dim outside the trim range.
                Rectangle().fill(.black.opacity(0.55)).frame(width: max(0, sx), height: height)
                Rectangle().fill(.black.opacity(0.55)).frame(width: max(0, w - ex), height: height).offset(x: ex)

                // Trim border.
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.accent, lineWidth: 2.5)
                    .frame(width: max(0, ex - sx), height: height).offset(x: sx)

                // Playhead.
                Capsule().fill(.white).frame(width: 3, height: height + 8)
                    .shadow(radius: 2).offset(x: max(0, x(model.current) - 1.5), y: -4)

                handle.offset(x: sx - 7)
                    .gesture(drag(in: w, dur: dur) {
                        model.trimStart = clamp($0, 0, model.trimEnd - 0.3, dur); model.seek(to: model.trimStart)
                    })
                handle.offset(x: ex - 7)
                    .gesture(drag(in: w, dur: dur) {
                        model.trimEnd = clamp($0, model.trimStart + 0.3, dur, dur); model.seek(to: model.trimEnd)
                    })
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(height: height)
    }

    private func filmstrip(width: CGFloat) -> some View {
        Group {
            if model.thumbnails.isEmpty {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            } else {
                HStack(spacing: 0) {
                    ForEach(model.thumbnails.indices, id: \.self) { i in
                        Image(nsImage: model.thumbnails[i]).resizable().scaledToFill()
                            .frame(width: width / CGFloat(model.thumbnails.count), height: height)
                            .clipped()
                    }
                }
            }
        }
        .frame(width: width, height: height)
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 5).fill(Theme.accent)
            .frame(width: 14, height: height + 8).offset(y: -4)
            .overlay(RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.9)).frame(width: 2.5, height: 22).offset(y: -4))
            .shadow(color: .black.opacity(0.2), radius: 2)
    }

    private func drag(in width: CGFloat, dur: Double, _ update: @escaping (Double) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { v in update(Double(v.location.x / width) * dur) }
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double, _ dur: Double) -> Double {
        min(max(v, max(0, lo)), min(hi, dur))
    }
}
