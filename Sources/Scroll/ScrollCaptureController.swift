import SwiftUI
import AppKit

/// Drives scrolling capture: after a region is picked, it grabs that viewport on a timer while
/// the user scrolls, stitches frames, and returns one tall image when the user clicks Done.
@MainActor
@Observable
final class ScrollCaptureController {
    private(set) var frameCount = 0
    private(set) var capturedHeight = 0

    private let stitcher = ScrollStitcher()
    private var region: RegionSelection?
    private var timer: Timer?
    private var controlWindow: NSWindow?
    private var onDone: ((CGImage?, CGFloat) -> Void)?
    private var capturing = false

    func begin(region: RegionSelection, onDone: @escaping (CGImage?, CGFloat) -> Void) {
        self.region = region
        self.onDone = onDone
        frameCount = 0; capturedHeight = 0
        showControlBar()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let region, !capturing else { return }
        capturing = true
        Task {
            defer { capturing = false }
            if let cg = try? await CaptureEngine.shared.captureRegionImage(
                displayID: region.displayID, scale: region.scale, sourceRect: region.sourceRect) {
                capturedHeight = stitcher.add(cg)
                frameCount = stitcher.frameCount
            }
        }
    }

    func finish() {
        timer?.invalidate(); timer = nil
        hideControlBar()
        let composed = stitcher.compose()
        let scale = CGFloat(region?.scale ?? 2)
        onDone?(composed, scale)
        onDone = nil
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        hideControlBar()
        onDone?(nil, 0)
        onDone = nil
    }

    // MARK: Control bar

    private func showControlBar() {
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 52),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        win.level = .statusBar
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        win.contentView = NSHostingView(rootView: ScrollBar(controller: self,
                                                            onDone: { [weak self] in self?.finish() },
                                                            onCancel: { [weak self] in self?.cancel() }))
        if let screen = NSScreen.main {
            win.setFrameOrigin(CGPoint(x: screen.frame.midX - 150, y: screen.visibleFrame.maxY - 52 - 10))
        }
        win.orderFrontRegardless()
        controlWindow = win
    }

    private func hideControlBar() {
        controlWindow?.orderOut(nil)
        controlWindow = nil
    }
}

/// The floating scrolling-capture control bar.
private struct ScrollBar: View {
    @Bindable var controller: ScrollCaptureController
    let onDone: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "arrow.down.doc")
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text("Scroll to capture").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Text("\(controller.frameCount) frames").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: Theme.Space.sm)
            Button("Cancel", action: onCancel)
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .background(.black.opacity(0.85), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
    }
}
