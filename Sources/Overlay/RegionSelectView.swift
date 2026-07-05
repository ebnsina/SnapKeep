import AppKit

/// The interactive selection surface: draws the frozen screenshot dimmed, with a bright
/// cutout for the current selection, live dimensions, crosshair guides, and a magnifier loupe.
final class RegionSelectView: NSView {
    private let frozen: NSImage
    private let onComplete: (CGRect?) -> Void
    private let cornerRadius: CGFloat = 12 // rounded-xl

    private var startPoint: CGPoint?
    private var currentRect: CGRect = .zero
    private var mouseLocation: CGPoint = .zero
    private var isDragging = false

    init(frame: CGRect, frozen: NSImage, onComplete: @escaping (CGRect?) -> Void) {
        self.frozen = frozen
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

        // 1. Sharp screenshot everywhere — you always see what you're capturing.
        frozen.draw(in: bounds)

        let hasSelection = currentRect.width > 0 && currentRect.height > 0

        if hasSelection {
            // 2. Dim only OUTSIDE the selection; keep the rounded-xl selection crisp.
            let radius = min(cornerRadius, min(currentRect.width, currentRect.height) / 2)
            let path = NSBezierPath(roundedRect: currentRect, xRadius: radius, yRadius: radius)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
            ctx.fill(bounds)
            ctx.saveGState()
            path.addClip()
            frozen.draw(in: bounds) // restore full brightness inside the selection
            ctx.restoreGState()

            drawSelectionBorder(path)
            drawDimensionPill()
        } else {
            // Before dragging: a light dim + crosshair, screen still clearly visible.
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.12).cgColor)
            ctx.fill(bounds)
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
    /// A macOS-style magnifier pinned near the cursor: a rounded card with a crisp zoomed
    /// pixel grid, a highlighted center pixel, and a hex + size readout below.
    private func drawLoupe(_ ctx: CGContext) {
        guard let cg = frozen.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let scale = window?.backingScaleFactor ?? 2

        let zoomSize: CGFloat = 108      // zoom area (square)
        let readoutH: CGFloat = 40
        let cardW = zoomSize
        let cardH = zoomSize + readoutH
        let pixels = 11                  // odd, so there's a true center pixel
        let cell = zoomSize / CGFloat(pixels)

        // Position offset from the cursor, clamped to the screen.
        var x = mouseLocation.x + 22, y = mouseLocation.y - cardH - 22
        if x + cardW > bounds.width { x = mouseLocation.x - cardW - 22 }
        if y < 0 { y = mouseLocation.y + 22 }
        let card = CGRect(x: x, y: y, width: cardW, height: cardH)
        let zoomRect = CGRect(x: x, y: y + readoutH, width: zoomSize, height: zoomSize)

        // Card background.
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)
        NSColor.black.withAlphaComponent(0.85).setFill()
        cardPath.fill()

        // Zoomed pixels (nearest-neighbor for a crisp grid).
        ctx.saveGState()
        NSBezierPath(roundedRect: zoomRect.insetBy(dx: 3, dy: 3), xRadius: 8, yRadius: 8).addClip()
        let samplePts = CGFloat(pixels)
        let srcRect = CGRect(x: (mouseLocation.x - samplePts / 2) * scale,
                             y: (bounds.height - mouseLocation.y - samplePts / 2) * scale,
                             width: samplePts * scale, height: samplePts * scale)
        var centerColor = NSColor.black
        if let cropped = cg.cropping(to: srcRect) {
            ctx.interpolationQuality = .none
            ctx.draw(cropped, in: zoomRect.insetBy(dx: 3, dy: 3))
            if let rep = readCenterPixel(cropped) { centerColor = rep }
        }
        // subtle pixel grid
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
        ctx.setLineWidth(0.5)
        for i in 1..<pixels {
            let gx = zoomRect.minX + CGFloat(i) * cell
            let gy = zoomRect.minY + CGFloat(i) * cell
            ctx.move(to: CGPoint(x: gx, y: zoomRect.minY)); ctx.addLine(to: CGPoint(x: gx, y: zoomRect.maxY))
            ctx.move(to: CGPoint(x: zoomRect.minX, y: gy)); ctx.addLine(to: CGPoint(x: zoomRect.maxX, y: gy))
        }
        ctx.strokePath()
        ctx.restoreGState()

        // Center pixel highlight.
        let centerCell = CGRect(x: zoomRect.midX - cell / 2, y: zoomRect.midY - cell / 2, width: cell, height: cell)
        ctx.setStrokeColor(brandColor.cgColor); ctx.setLineWidth(1.5); ctx.stroke(centerCell)

        // Readout: hex + size.
        let hex = hexString(centerColor)
        let size = currentRect.width > 0
            ? "\(Int(currentRect.width * scale))×\(Int(currentRect.height * scale))"
            : "\(Int(mouseLocation.x * scale)), \(Int((bounds.height - mouseLocation.y) * scale))"
        drawReadout(hex: hex, size: size, swatch: centerColor,
                    in: CGRect(x: x, y: y, width: cardW, height: readoutH))

        // Card border.
        brandColor.withAlphaComponent(0.9).setStroke()
        cardPath.lineWidth = 1; cardPath.stroke()
    }

    private func drawReadout(hex: String, size: String, swatch: NSColor, in rect: CGRect) {
        let mono = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        // color swatch
        let sw = CGRect(x: rect.minX + 8, y: rect.midY - 6, width: 12, height: 12)
        swatch.setFill(); NSBezierPath(roundedRect: sw, xRadius: 3, yRadius: 3).fill()
        NSColor.white.withAlphaComponent(0.3).setStroke(); NSBezierPath(roundedRect: sw, xRadius: 3, yRadius: 3).stroke()

        let hexAttrs: [NSAttributedString.Key: Any] = [.font: mono, .foregroundColor: NSColor.white]
        hex.draw(at: CGPoint(x: sw.maxX + 6, y: rect.midY + 1), withAttributes: hexAttrs)
        let sizeAttrs: [NSAttributedString.Key: Any] = [.font: mono, .foregroundColor: NSColor.white.withAlphaComponent(0.6)]
        size.draw(at: CGPoint(x: sw.maxX + 6, y: rect.midY - 12), withAttributes: sizeAttrs)
    }

    private func readCenterPixel(_ image: CGImage) -> NSColor? {
        let cx = image.width / 2, cy = image.height / 2
        guard let one = image.cropping(to: CGRect(x: cx, y: cy, width: 1, height: 1)) else { return nil }
        return NSBitmapImageRep(cgImage: one).colorAt(x: 0, y: 0)?
            .usingColorSpace(.deviceRGB)
    }

    private func hexString(_ color: NSColor) -> String {
        guard let c = color.usingColorSpace(.deviceRGB) else { return "#000000" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255),
                      Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }

    private var brandColor: NSColor { Theme.accentNS }
}
