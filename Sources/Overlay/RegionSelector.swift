import AppKit

/// A picked region for recording: the display and the crop rect (points, top-left origin).
struct RegionSelection {
    let displayID: CGDirectDisplayID
    let scale: Int
    let sourceRect: CGRect
}

/// A live (non-freezing) area selector: dims the display and lets the user drag a rectangle.
/// Used by region recording, where freezing the screen isn't wanted.
@MainActor
final class RegionSelectorController {
    private var window: NSWindow?
    private var continuation: CheckedContinuation<RegionSelection?, Never>?
    private var screen: NSScreen?

    func begin() async -> RegionSelection? {
        guard let target = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main else { return nil }
        screen = target

        return await withCheckedContinuation { cont in
            self.continuation = cont
            present(on: target)
        }
    }

    private func present(on screen: NSScreen) {
        let win = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                           backing: .buffered, defer: false)
        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = RegionSelectorView(frame: CGRect(origin: .zero, size: screen.frame.size)) { [weak self] rect in
            self?.finish(rect)
        }
        win.contentView = view
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    private func finish(_ rect: CGRect?) {
        window?.orderOut(nil)
        window = nil
        guard let rect, let screen, rect.width >= 8, rect.height >= 8 else {
            continuation?.resume(returning: nil); continuation = nil; return
        }
        let displayID = (screen.deviceDescription[.init("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
        // View points (bottom-left) → display points (top-left) for SCStreamConfiguration.sourceRect.
        let sourceRect = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY,
                                width: rect.width, height: rect.height)
        continuation?.resume(returning: RegionSelection(displayID: displayID,
                                                        scale: Int(screen.backingScaleFactor),
                                                        sourceRect: sourceRect))
        continuation = nil
    }
}

/// Dim + rubber-band selection surface.
private final class RegionSelectorView: NSView {
    private let onComplete: (CGRect?) -> Void
    private var start: CGPoint?
    private var rect: CGRect = .zero

    init(frame: CGRect, onComplete: @escaping (CGRect?) -> Void) {
        self.onComplete = onComplete
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        NSCursor.crosshair.set()
    }

    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil) }

    override func mouseDragged(with event: NSEvent) {
        guard let s = start else { return }
        let p = convert(event.locationInWindow, from: nil)
        rect = CGRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        onComplete(rect.width >= 8 && rect.height >= 8 ? rect : nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onComplete(nil) } // Esc
    }

    override func draw(_ dirtyRect: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.fill(bounds)
        guard rect.width > 0, rect.height > 0 else { return }
        ctx.setBlendMode(.clear); ctx.fill(rect); ctx.setBlendMode(.normal)

        ctx.setStrokeColor(Theme.accentNS.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(rect)

        let scale = window?.backingScaleFactor ?? 2
        let text = "\(Int(rect.width * scale)) × \(Int(rect.height * scale))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attrs)
        let pad: CGFloat = 6
        let pill = CGRect(x: rect.minX, y: rect.maxY + 8, width: size.width + pad * 2, height: size.height + pad * 2)
        Theme.accentNS.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
        text.draw(at: CGPoint(x: pill.minX + pad, y: pill.minY + pad), withAttributes: attrs)
    }
}
