import AppKit

/// The interactive selection surface: draws the frozen screenshot dimmed, with a bright
/// cutout for the current selection, live dimensions, crosshair guides, and a magnifier loupe.
final class RegionSelectView: NSView {
    private let frozen: NSImage
    private let blurred: NSImage
    private let onComplete: (CGRect?) -> Void
    private let cornerRadius: CGFloat = 12 // rounded-xl

    private var startPoint: CGPoint?
    private var currentRect: CGRect = .zero
    private var mouseLocation: CGPoint = .zero
    private var isDragging = false

    init(frame: CGRect, frozen: NSImage, blurred: NSImage, onComplete: @escaping (CGRect?) -> Void) {
        self.frozen = frozen
        self.blurred = blurred
        self.onComplete = onComplete
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeAlways, .mouseMoved, .inVisibleRect],
                                       owner: self, userInfo: nil))
        NSCursor.crosshair.set()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        isDragging = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        mouseLocation = p
        if let s = startPoint {
            currentRect = CGRect(x: min(s.x, p.x), y: min(s.y, p.y),
                                 width: abs(p.x - s.x), height: abs(p.y - s.y))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        if currentRect.width >= 4, currentRect.height >= 4 {
            onComplete(currentRect)
        } else {
            onComplete(nil) // treat a click/tiny drag as cancel
        }
    }

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onComplete(nil) } // Esc
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. Blurred screenshot as the backdrop, with a light dim for contrast.
        blurred.draw(in: bounds)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.22).cgColor)
        ctx.fill(bounds)

        let hasSelection = currentRect.width > 0 && currentRect.height > 0

        if hasSelection {
            // 2. Show the crisp screenshot inside a rounded-xl selection window.
            let radius = min(cornerRadius, min(currentRect.width, currentRect.height) / 2)
            let path = NSBezierPath(roundedRect: currentRect, xRadius: radius, yRadius: radius)
            ctx.saveGState()
            path.addClip()
            frozen.draw(in: bounds)
            ctx.restoreGState()

            drawSelectionBorder(path)
            drawDimensionPill()
        } else {
            drawCrosshair(ctx)
        }

        if !hasSelection || isDragging { drawLoupe(ctx) }
    }

    private func drawSelectionBorder(_ path: NSBezierPath) {
        brandColor.setStroke()
        path.lineWidth = 2
        path.stroke()

        // Corner handles.
        let handle: CGFloat = 6
        brandColor.setFill()
        for corner in [CGPoint(x: currentRect.minX, y: currentRect.minY),
                       CGPoint(x: currentRect.maxX, y: currentRect.minY),
                       CGPoint(x: currentRect.minX, y: currentRect.maxY),
                       CGPoint(x: currentRect.maxX, y: currentRect.maxY)] {
            NSBezierPath(ovalIn: CGRect(x: corner.x - handle/2, y: corner.y - handle/2,
                                        width: handle, height: handle)).fill()
        }
    }

    private func drawCrosshair(_ ctx: CGContext) {
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: mouseLocation.x, y: 0))
        ctx.addLine(to: CGPoint(x: mouseLocation.x, y: bounds.height))
        ctx.move(to: CGPoint(x: 0, y: mouseLocation.y))
        ctx.addLine(to: CGPoint(x: bounds.width, y: mouseLocation.y))
        ctx.strokePath()
    }

    private func drawDimensionPill() {
        let scale = window?.backingScaleFactor ?? 2
        let text = "\(Int(currentRect.width * scale)) × \(Int(currentRect.height * scale))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attrs)
        let pad: CGFloat = 6
        var origin = CGPoint(x: currentRect.minX, y: currentRect.maxY + 8)
        if origin.y + size.height + pad*2 > bounds.height { origin.y = currentRect.minY - size.height - pad*2 - 8 }

        let pill = CGRect(x: origin.x, y: origin.y, width: size.width + pad*2, height: size.height + pad*2)
        let path = NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6)
        brandColor.setFill()
        path.fill()
        text.draw(at: CGPoint(x: pill.minX + pad, y: pill.minY + pad), withAttributes: attrs)
    }

    /// Zoomed circular loupe showing pixels + hex color under the cursor.
    private func drawLoupe(_ ctx: CGContext) {
        guard let cg = frozen.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let scale = window?.backingScaleFactor ?? 2
        let loupeSize: CGFloat = 96
        let zoom: CGFloat = 8
        let sample = loupeSize / zoom // points sampled around cursor

        var pos = CGPoint(x: mouseLocation.x + 20, y: mouseLocation.y + 20)
        if pos.x + loupeSize > bounds.width { pos.x = mouseLocation.x - 20 - loupeSize }
        if pos.y + loupeSize > bounds.height { pos.y = mouseLocation.y - 20 - loupeSize }
        let loupeRect = CGRect(x: pos.x, y: pos.y, width: loupeSize, height: loupeSize)

        ctx.saveGState()
        NSBezierPath(ovalIn: loupeRect).addClip()
        // Source pixels (top-left origin) around the cursor.
        let srcX = (mouseLocation.x - sample/2) * scale
        let srcY = (bounds.height - mouseLocation.y - sample/2) * scale
        let srcRect = CGRect(x: srcX, y: srcY, width: sample*scale, height: sample*scale)
        if let cropped = cg.cropping(to: srcRect) {
            ctx.interpolationQuality = .none
            ctx.draw(cropped, in: loupeRect) // draws right-side up in non-flipped view
        }
        ctx.restoreGState()

        // Ring + crosshair.
        ctx.setStrokeColor(brandColor.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: loupeRect)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: loupeRect.midX, y: loupeRect.minY))
        ctx.addLine(to: CGPoint(x: loupeRect.midX, y: loupeRect.maxY))
        ctx.move(to: CGPoint(x: loupeRect.minX, y: loupeRect.midY))
        ctx.addLine(to: CGPoint(x: loupeRect.maxX, y: loupeRect.midY))
        ctx.strokePath()
    }

    private var brandColor: NSColor { Theme.accentNS }
}
