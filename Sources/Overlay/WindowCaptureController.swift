import AppKit

/// Result of a window capture.
struct WindowCapture {
    let cgImage: CGImage
    let scale: CGFloat
}

/// Hover-to-highlight window picker: dims the screen, highlights the window under the
/// cursor, and captures it on click. Esc cancels.
@MainActor
final class WindowCaptureController {
    private var window: NSWindow?
    private var continuation: CheckedContinuation<WindowCapture?, Never>?
    private var windows: [CaptureEngine.WindowInfo] = []

    func begin() async -> WindowCapture? {
        do {
            windows = try await CaptureEngine.shared.listWindows()
        } catch {
            NSLog("SnapKeep window list failed: \(error.localizedDescription)")
            return nil
        }
        guard !windows.isEmpty else { return nil }

        return await withCheckedContinuation { cont in
            self.continuation = cont
            presentOverlay()
        }
    }

    private func presentOverlay() {
        // One overlay spanning the union of all screens.
        let unionFrame = NSScreen.screens.reduce(CGRect.zero) { $0.union($1.frame) }
        let win = NSWindow(contentRect: unionFrame, styleMask: .borderless,
                           backing: .buffered, defer: false)
        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = WindowPickView(frame: CGRect(origin: .zero, size: unionFrame.size),
                                  originOffset: unionFrame.origin,
                                  windows: windows) { [weak self] picked in
            self?.finish(with: picked)
        }
        win.contentView = view
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    private func finish(with id: CGWindowID?) {
        window?.orderOut(nil)
        window = nil
        guard let id else {
            continuation?.resume(returning: nil); continuation = nil; return
        }
        let scale = Int(NSScreen.main?.backingScaleFactor ?? 2)
        Task {
            do {
                let cg = try await CaptureEngine.shared.captureWindow(id: id, scale: scale)
                continuation?.resume(returning: WindowCapture(cgImage: cg, scale: CGFloat(scale)))
            } catch {
                continuation?.resume(returning: nil)
            }
            continuation = nil
        }
    }
}

/// The dim + highlight surface for window picking.
private final class WindowPickView: NSView {
    private let windows: [CaptureEngine.WindowInfo]
    private let originOffset: CGPoint
    private let onPick: (CGWindowID?) -> Void
    private var hovered: CaptureEngine.WindowInfo?

    init(frame: CGRect, originOffset: CGPoint, windows: [CaptureEngine.WindowInfo],
         onPick: @escaping (CGWindowID?) -> Void) {
        self.windows = windows
        self.originOffset = originOffset
        self.onPick = onPick
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeAlways, .mouseMoved, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    /// Convert a global-screen frame (bottom-left origin) into this view's local space.
    private func localRect(_ global: CGRect) -> CGRect {
        CGRect(x: global.origin.x - originOffset.x, y: global.origin.y - originOffset.y,
               width: global.width, height: global.height)
    }

    override func mouseMoved(with event: NSEvent) {
        let global = CGPoint(x: NSEvent.mouseLocation.x, y: NSEvent.mouseLocation.y)
        // Topmost (first in list) window whose frame contains the cursor.
        hovered = windows.first { $0.frame.contains(global) }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onPick(hovered?.id)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onPick(nil) } // Esc
    }

    override func draw(_ dirtyRect: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.fill(bounds)

        guard let hovered else { return }
        let rect = localRect(hovered.frame)
        // Punch a clear hole so the window reads at full brightness.
        ctx.setBlendMode(.clear)
        ctx.fill(rect)
        ctx.setBlendMode(.normal)

        ctx.setStrokeColor(Theme.accentNS.cgColor)
        ctx.setLineWidth(3)
        ctx.stroke(rect)

        drawLabel("\(hovered.app)  ·  click to capture", at: rect)
    }

    private func drawLabel(_ text: String, at rect: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attrs)
        let pad: CGFloat = 7
        let pill = CGRect(x: rect.midX - (size.width + pad*2)/2,
                          y: rect.midY - (size.height + pad*2)/2,
                          width: size.width + pad*2, height: size.height + pad*2)
        Theme.accentNS.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 7, yRadius: 7).fill()
        text.draw(at: CGPoint(x: pill.minX + pad, y: pill.minY + pad), withAttributes: attrs)
    }
}
