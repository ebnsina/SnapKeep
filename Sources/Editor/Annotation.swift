import AppKit

/// A single drawn mark on a capture. One value type covers every tool; `render(in:)`
/// is shared by the live canvas and the final export so what you see is what you save.
struct Annotation: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case pen, marker, line, arrow, rect, ellipse, text, step, pixelate
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .pen: return "pencil.tip"
            case .marker: return "highlighter"
            case .line: return "line.diagonal"
            case .arrow: return "arrow.up.right"
            case .rect: return "rectangle"
            case .ellipse: return "circle"
            case .text: return "textformat"
            case .step: return "1.circle.fill"
            case .pixelate: return "mosaic"
            }
        }

        var title: String {
            switch self {
            case .pen: return "Pen"
            case .marker: return "Marker"
            case .line: return "Line"
            case .arrow: return "Arrow"
            case .rect: return "Rectangle"
            case .ellipse: return "Ellipse"
            case .text: return "Text"
            case .step: return "Step number"
            case .pixelate: return "Pixelate / redact"
            }
        }

        /// Tools placed with a single click rather than a drag.
        var isClickToPlace: Bool { self == .step }
    }

    let id = UUID()
    var kind: Kind
    /// pen/marker: the full freehand path. line/arrow/rect/ellipse: [start, end]. text: [anchor].
    var points: [CGPoint]
    var color: NSColor
    var lineWidth: CGFloat
    var text: String = ""
    var fontSize: CGFloat = 20

    // MARK: Rendering

    /// `base`/`scale` are only needed by pixelate (to sample the underlying pixels).
    func render(in ctx: CGContext, base: CGImage? = nil, scale: CGFloat = 1) {
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(color.cgColor)
        ctx.setFillColor(color.cgColor)
        ctx.setLineWidth(lineWidth)

        switch kind {
        case .pen:
            strokePath(ctx, points: points)
        case .marker:
            ctx.setStrokeColor(color.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(max(lineWidth * 3, 14))
            strokePath(ctx, points: points)
        case .line:
            guard let a = points.first, let b = points.last else { break }
            ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
        case .arrow:
            guard let a = points.first, let b = points.last else { break }
            drawArrow(ctx, from: a, to: b)
        case .rect:
            guard points.count >= 2 else { break }
            ctx.stroke(rect(points[0], points[1]))
        case .ellipse:
            guard points.count >= 2 else { break }
            ctx.strokeEllipse(in: rect(points[0], points[1]))
        case .text:
            drawText(ctx)
        case .step:
            drawStep(ctx)
        case .pixelate:
            drawPixelate(ctx, base: base, scale: scale)
        }
        ctx.restoreGState()
    }

    /// Numbered badge (the number is stored in `text`).
    private func drawStep(_ ctx: CGContext) {
        guard let center = points.first else { return }
        let radius = max(lineWidth * 4, 14)
        let box = CGRect(x: center.x - radius, y: center.y - radius, width: radius*2, height: radius*2)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: box)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: box)

        let label = text.isEmpty ? "1" : text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: radius, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let size = label.size(withAttributes: attrs)
        let gctx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gctx
        label.draw(at: CGPoint(x: center.x - size.width/2, y: center.y - size.height/2), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Pixelate the underlying capture inside the selected rect (privacy redaction).
    private func drawPixelate(_ ctx: CGContext, base: CGImage?, scale: CGFloat) {
        guard points.count >= 2, let base else { return }
        let r = rect(points[0], points[1])
        guard r.width > 1, r.height > 1 else { return }
        // Point space (bottom-left) → base pixels (top-left).
        let src = CGRect(x: r.minX * scale,
                         y: CGFloat(base.height) - r.maxY * scale,
                         width: r.width * scale, height: r.height * scale)
        guard let cropped = base.cropping(to: src),
              let pixels = Annotation.pixelate(cropped) else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.draw(pixels, in: r)
        ctx.restoreGState()
    }

    /// Downscale-then-upscale to produce a chunky mosaic.
    static func pixelate(_ image: CGImage, blocks: Int = 14) -> CGImage? {
        let ratio = CGFloat(image.height) / CGFloat(max(image.width, 1))
        let smallW = max(1, blocks)
        let smallH = max(1, Int(CGFloat(blocks) * ratio))
        guard let ctx = CGContext(data: nil, width: smallW, height: smallH, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
        return ctx.makeImage()
    }

    private func strokePath(_ ctx: CGContext, points: [CGPoint]) {
        guard let first = points.first else { return }
        ctx.move(to: first)
        for p in points.dropFirst() { ctx.addLine(to: p) }
        ctx.strokePath()
    }

    private func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func drawArrow(_ ctx: CGContext, from a: CGPoint, to b: CGPoint) {
        ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
        let angle = atan2(b.y - a.y, b.x - a.x)
        let head = max(lineWidth * 3.5, 12)
        let wing = CGFloat.pi / 7
        let p1 = CGPoint(x: b.x - head * cos(angle - wing), y: b.y - head * sin(angle - wing))
        let p2 = CGPoint(x: b.x - head * cos(angle + wing), y: b.y - head * sin(angle + wing))
        ctx.move(to: b); ctx.addLine(to: p1)
        ctx.addLine(to: p2); ctx.addLine(to: b)
        ctx.fillPath()
    }

    private func drawText(_ ctx: CGContext) {
        guard let anchor = points.first, !text.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color
        ]
        let ns = NSAttributedString(string: text, attributes: attrs)
        let gctx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gctx
        ns.draw(at: anchor)
        NSGraphicsContext.restoreGraphicsState()
    }
}
