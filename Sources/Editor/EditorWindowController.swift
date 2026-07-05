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
            styleMask: [.titled, .closable],
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

    /// Window content size for a given canvas size (toolbar chrome + a sensible min width).
    private func contentSize(for canvas: CGSize) -> CGSize {
        CGSize(width: max(canvas.width, 560), height: canvas.height + 72)
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
                .frame(width: state.displaySize.width, height: state.displaySize.height)
            EditorToolbar(state: state, onCopy: onCopy, onSave: onSave,
                          onShare: onShare, onCopyText: onCopyText,
                          onBeautify: onBeautify, onPrint: onPrint, onClose: onClose)
                .padding(.vertical, Theme.Space.md)
        }
        .background(.black)
    }
}

private struct CanvasRepresentable: NSViewRepresentable {
    let state: EditorState
    func makeNSView(context: Context) -> AnnotationCanvasView { AnnotationCanvasView(state: state) }
    func updateNSView(_ nsView: AnnotationCanvasView, context: Context) {
        // Keep the AppKit view in step with the (possibly cropped/rotated) canvas size.
        if nsView.frame.size != state.displaySize {
            nsView.frame = CGRect(origin: .zero, size: state.displaySize)
        }
        nsView.needsDisplay = true
    }
}
