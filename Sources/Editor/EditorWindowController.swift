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

    func present(cgImage: CGImage, scale: CGFloat, completion: @escaping (Result) -> Void) {
        let state = EditorState(cgImage: cgImage, scale: scale)
        self.state = state
        self.completion = completion

        let root = EditorRootView(
            state: state,
            onCopy: { [weak self] in self?.copy() },
            onSave: { [weak self] in self?.save() },
            onClose: { [weak self] in self?.finish(.closed) }
        )

        let hosting = NSHostingView(rootView: root)
        let size = state.displaySize
        let win = NSWindow(
            contentRect: CGRect(origin: .zero, size: CGSize(width: size.width, height: size.height + 72)),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        win.title = "\(Brand.name) — Edit"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.contentView = hosting
        win.center()
        win.makeKeyAndOrderFront(nil)
        win.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
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
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CanvasRepresentable(state: state)
                .frame(width: state.displaySize.width, height: state.displaySize.height)
            EditorToolbar(state: state, onCopy: onCopy, onSave: onSave, onClose: onClose)
                .padding(.vertical, Theme.Space.md)
        }
        .background(.black)
    }
}

private struct CanvasRepresentable: NSViewRepresentable {
    let state: EditorState
    func makeNSView(context: Context) -> AnnotationCanvasView { AnnotationCanvasView(state: state) }
    func updateNSView(_ nsView: AnnotationCanvasView, context: Context) {}
}
