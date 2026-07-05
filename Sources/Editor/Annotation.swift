import AppKit

/// A single drawn mark on a capture. One value type covers every tool; `render(in:)`
/// is shared by the live canvas and the final export so what you see is what you save.
struct Annotation: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case pen, marker, line, arrow, rect, ellipse, text
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
            }
        }
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

    func render(in ctx: CGContext) {
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
        }
        ctx.restoreGState()
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
