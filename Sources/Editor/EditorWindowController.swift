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
            onClose: { [weak self] in self?.finish(.closed) }
        )

        let hosting = NSHostingView(rootView: root)
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
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CanvasRepresentable(state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            EditorToolbar(state: state, onCopy: onCopy, onSave: onSave,
                          onShare: onShare, onCopyText: onCopyText,
                          onBeautify: onBeautify, onPrint: onPrint, onClose: onClose)
                .padding(.vertical, Theme.Space.md)
        }
        .background(.black)
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
