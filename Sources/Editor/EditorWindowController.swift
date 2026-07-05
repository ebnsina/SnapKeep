import SwiftUI
import AppKit

/// Hosts the post-capture editor in its own window. Presents the canvas with the floating
/// toolbar overlaid, and reports back what the user did (copied, saved, or closed).
@MainActor
final class EditorWindowController {
    enum Result { case saved(URL), copied, closed }

    private var window: NSWindow?
    private var state: EditorState?
    private var completion: ((Result) -> Void)?
    private var beautifyWindow: BeautifyWindowController?

    func present(cgImage: CGImage, scale: CGFloat, completion: @escaping (Result) -> Void) {
        let state = EditorState(cgImage: cgImage, scale: scale)
        self.state = state
        self.completion = completion

        let root = EditorRootView(
            state: state,
            onCopy: { [weak self] in self?.copy() },
            onSave: { [weak self] in self?.save() },
            onShare: { [weak self] in self?.share() },
            onCopyText: { [weak self] in self?.copyText() },
            onBeautify: { [weak self] in self?.beautify() },
            onPrint: { [weak self] in self?.printCapture() },
            onRedact: { [weak self] in self?.redact() },
            onRemoveBg: { [weak self] in self?.removeBackground() },
            onClose: { [weak self] in self?.finish(.closed) }
        )

        let hosting = FirstMouseHostingView(rootView: AnyView(root))
        let win = NSWindow(
            contentRect: CGRect(origin: .zero, size: contentSize(for: state.displaySize)),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        win.title = "\(Brand.name) — Edit"
        // The canvas handles its own drags for drawing, so the window must NOT move on a
        // background drag. Use the title bar to move the window instead.
        win.isMovableByWindowBackground = false
        win.contentView = hosting
        win.center()
        win.makeKeyAndOrderFront(nil)
        win.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        self.window = win

        // Crop/rotate change the canvas size — resize the window to fit.
        state.onGeometryChange = { [weak self] in self?.resizeToFit() }
        // Esc (with nothing to cancel) closes the editor.
        state.onCancel = { [weak self] in self?.finish(.closed) }
    }

    /// Window content size, capped to the screen so the toolbar is always visible (tall
    /// captures scroll inside the canvas rather than pushing the toolbar off-screen).
    private func contentSize(for canvas: CGSize) -> CGSize {
        let vis = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1400, height: 900)
        let toolbar: CGFloat = 72
        let w = min(max(canvas.width, 560), vis.width - 40)
        let h = min(canvas.height + toolbar, vis.height - 60)
        return CGSize(width: w, height: h)
    }

    private func resizeToFit() {
        guard let window, let state else { return }
        window.setContentSize(contentSize(for: state.displaySize))
        window.center()
    }

    private func copy() {
        guard let state else { return }
        CaptureStore.copyToClipboard(state.flatten())
        finish(.copied)
    }

    private func save() {
        guard let state else { return }
        do {
            let url = try CaptureStore.savePNG(state.flatten())
            CaptureStore.copyToClipboard(state.flatten())
            finish(.saved(url))
        } catch {
            finish(.closed)
        }
    }

    /// OCR the base capture and copy the recognized text to the clipboard.
    private func copyText() {
        guard let state else { return }
        let base = state.baseImage
        Task {
            let text = await TextRecognizer.recognize(in: base)
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text.isEmpty ? "" : text, forType: .string)
        }
    }

    /// Print the current flattened capture, scaled to fit the page.
    private func printCapture() {
        guard let state else { return }
        let image = state.flatten()
        let imageView = NSImageView(frame: CGRect(origin: .zero, size: image.size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.orientation = image.size.width >= image.size.height ? .landscape : .portrait
        let op = NSPrintOperation(view: imageView, printInfo: info)
        op.run()
    }

    /// Auto-detect faces / emails / card numbers and cover them with pixelate annotations.
    private func redact() {
        guard let state else { return }
        let base = state.baseImage
        let size = state.displaySize
        Task {
            let norm = await SmartRedactor.detect(in: base)
            guard let state = self.state, !norm.isEmpty else { NSSound.beep(); return }
            let annotations = norm.map { r -> Annotation in
                // Normalized (bottom-left) → point space, padded a little for full coverage.
                var rect = CGRect(x: r.minX * size.width, y: r.minY * size.height,
                                  width: r.width * size.width, height: r.height * size.height)
                rect = rect.insetBy(dx: -rect.width * 0.06, dy: -rect.height * 0.06)
                return Annotation(kind: .pixelate,
                                  points: [CGPoint(x: rect.minX, y: rect.minY),
                                           CGPoint(x: rect.maxX, y: rect.maxY)],
                                  color: state.color, lineWidth: state.lineWidth)
            }
            state.addAll(annotations)
        }
    }

    /// Lift the subject out of the capture (transparent background).
    private func removeBackground() {
        guard let state else { return }
        let base = state.baseImage
        Task {
            if let cut = await BackgroundRemover.removeBackground(from: base), let state = self.state {
                state.replaceBase(cut)
            } else {
                NSSound.beep()
            }
        }
    }

    /// Open the Beautify window with the current flattened capture.
    private func beautify() {
        guard let state else { return }
        let controller = BeautifyWindowController()
        beautifyWindow = controller
        controller.onClose = { [weak self] _ in self?.beautifyWindow = nil }
        controller.present(image: state.flatten())
    }

    /// Present the native share sheet for the current (flattened) capture.
    private func share() {
        guard let state, let view = window?.contentView else { return }
        let name = CaptureStore.suggestedName()
        guard let url = ShareHelper.temporaryPNG(for: state.flatten(), name: name) else { return }
        ShareHelper.present(items: [url], from: view)
    }

    private func finish(_ result: Result) {
        window?.orderOut(nil)
        window = nil
        state = nil
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }
}

/// SwiftUI wrapper: the annotation canvas with the floating toolbar pinned to the bottom.
private struct EditorRootView: View {
    @Bindable var state: EditorState
    let onCopy: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onCopyText: () -> Void
    let onBeautify: () -> Void
    let onPrint: () -> Void
    let onRedact: () -> Void
    let onRemoveBg: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CanvasRepresentable(state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            EditorToolbar(state: state, onCopy: onCopy, onSave: onSave,
                          onShare: onShare, onCopyText: onCopyText,
                          onBeautify: onBeautify, onPrint: onPrint,
                          onRedact: onRedact, onRemoveBg: onRemoveBg, onClose: onClose)
                .padding(.vertical, Theme.Space.md)
        }
        .background(Color(red: 0.11, green: 0.11, blue: 0.13)) // neutral editor mat
    }
}

/// Hosts the annotation canvas in an AppKit scroll view so large/tall captures scroll while
/// the toolbar stays put. The canvas stays full-resolution; mouse coords convert correctly.
private struct CanvasRepresentable: NSViewRepresentable {
    let state: EditorState

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let canvas = AnnotationCanvasView(state: state)
        canvas.frame = CGRect(origin: .zero, size: state.displaySize)
        let scroll = NSScrollView()
        scroll.contentView = CenteringClipView() // center the canvas when smaller than the viewport
        scroll.documentView = canvas
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        context.coordinator.lastSize = state.displaySize
        DispatchQueue.main.async { scrollToTop(scroll) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let canvas = scroll.documentView as? AnnotationCanvasView else { return }
        if canvas.frame.size != state.displaySize {
            canvas.frame = CGRect(origin: .zero, size: state.displaySize)
            if context.coordinator.lastSize != state.displaySize {
                context.coordinator.lastSize = state.displaySize
                DispatchQueue.main.async { scrollToTop(scroll) }
            }
        }
        canvas.needsDisplay = true
    }

    /// Non-flipped canvas: the top row sits at the max Y, so scroll there.
    private func scrollToTop(_ scroll: NSScrollView) {
        guard let doc = scroll.documentView else { return }
        doc.scrollToVisible(NSRect(x: 0, y: doc.frame.height - 1, width: 1, height: 1))
    }

    final class Coordinator { var lastSize: CGSize = .zero }
}

/// Hosting view that accepts the first mouse click even when the window isn't key, so toolbar
/// actions always register (no swallowed "activate the window" first click).
private final class FirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    required init(rootView: AnyView) { super.init(rootView: rootView) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

/// Keeps the canvas centered in the scroll view when it's smaller than the viewport, so a
/// narrow/short capture sits on a neutral mat instead of pinned to a corner.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        if rect.width > doc.frame.width { rect.origin.x = (doc.frame.width - rect.width) / 2 }
        if rect.height > doc.frame.height { rect.origin.y = (doc.frame.height - rect.height) / 2 }
        return rect
    }
}
