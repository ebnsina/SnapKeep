import AppKit

/// Renders the capture plus every annotation and turns mouse input into new annotations.
/// Drawing happens in point space; `EditorState.flatten()` replays the same marks at full res.
final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    private let state: EditorState
    private var draft: Annotation?
    private var activeTextField: NSTextField?

    // Select-tool drag state.
    private var moveLast: CGPoint?
    private var didCheckpointMove = false

    // Resize state.
    private var resizeOriginal: Annotation?
    private var resizeAnchor: CGPoint?
    private var resizeStartCorner: CGPoint?

    // Crop-tool drag state.
    private var cropStart: CGPoint?
    private var cropRect: CGRect?

    init(state: EditorState) {
        self.state = state
        super.init(frame: CGRect(origin: .zero, size: state.displaySize))
        // Redraw committed marks whenever the model changes (undo/redo/add).
        state.onChange = { [weak self] in self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Grab focus so Delete/Esc work without a click first.
        DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(self) }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.draw(state.baseImage, in: bounds) // scales pixels → points
        for annotation in state.annotations {
            annotation.render(in: ctx, base: state.baseImage, scale: state.scale)
        }
        draft?.render(in: ctx, base: state.baseImage, scale: state.scale)

        // Crop overlay: dim outside the dragged rect.
        if state.tool == .crop, let r = cropRect, r.width > 0, r.height > 0 {
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
            ctx.fill(bounds)
            ctx.setBlendMode(.clear); ctx.fill(r); ctx.setBlendMode(.normal)
            ctx.saveGState(); ctx.clip(to: r); ctx.draw(state.baseImage, in: bounds); ctx.restoreGState()
            for a in state.annotations { a.render(in: ctx, base: state.baseImage, scale: state.scale) }
            ctx.setStrokeColor(Theme.accentNS.cgColor); ctx.setLineWidth(1.5); ctx.stroke(r)
        }

        // Selection outline + resize handles for the Select tool.
        if state.tool == .select, let idx = state.selectedIndex {
            let rect = handleBounds(state.annotations[idx])
            ctx.setStrokeColor(Theme.accentNS.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [5, 3])
            ctx.stroke(rect)
            ctx.setLineDash(phase: 0, lengths: [])
            // Corner handles.
            ctx.setLineDash(phase: 0, lengths: [])
            for c in corners(rect) {
                let h = CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)
                ctx.setFillColor(NSColor.white.cgColor); ctx.fillEllipse(in: h)
                ctx.setStrokeColor(Theme.accentNS.cgColor); ctx.setLineWidth(1.5); ctx.strokeEllipse(in: h)
            }
        }
    }

    // MARK: Resize helpers

    /// Bounds used for the selection outline + handles.
    private func handleBounds(_ a: Annotation) -> CGRect { a.bounds.insetBy(dx: -4, dy: -4) }

    /// Corners in a fixed order: 0 BL, 1 BR, 2 TL, 3 TR (so 3 - i is the diagonal opposite).
    private func corners(_ b: CGRect) -> [CGPoint] {
        [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
         CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY)]
    }

    /// Index of the handle near `p`, or nil.
    private func resizeCornerHit(at p: CGPoint, annotation: Annotation) -> Int? {
        let b = handleBounds(annotation)
        for (i, c) in corners(b).enumerated() where hypot(p.x - c.x, p.y - c.y) <= 10 { return i }
        return nil
    }

    private func resizeAnnotation(at idx: Int, original orig: Annotation,
                                  anchor: CGPoint, start: CGPoint, to p: CGPoint) {
        let minGap: CGFloat = 8
        var q = p
        if abs(q.x - anchor.x) < minGap { q.x = anchor.x + (start.x >= anchor.x ? minGap : -minGap) }
        if abs(q.y - anchor.y) < minGap { q.y = anchor.y + (start.y >= anchor.y ? minGap : -minGap) }
        let sx = (start.x - anchor.x) == 0 ? 1 : (q.x - anchor.x) / (start.x - anchor.x)
        let sy = (start.y - anchor.y) == 0 ? 1 : (q.y - anchor.y) / (start.y - anchor.y)

        var updated = orig
        updated.points = orig.points.map {
            CGPoint(x: anchor.x + ($0.x - anchor.x) * sx, y: anchor.y + ($0.y - anchor.y) * sy)
        }
        let avg = (abs(sx) + abs(sy)) / 2
        if orig.kind == .text { updated.fontSize = max(8, orig.fontSize * avg) }
        if orig.kind == .step { updated.lineWidth = max(1, orig.lineWidth * avg) }
        state.annotations[idx] = updated
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        if state.tool == .select {
            window?.makeFirstResponder(self) // so Delete removes the selection
            // If a corner handle of the selected annotation is grabbed, start resizing.
            if let idx = state.selectedIndex,
               let corner = resizeCornerHit(at: p, annotation: state.annotations[idx]) {
                state.checkpoint()
                let b = handleBounds(state.annotations[idx])
                resizeOriginal = state.annotations[idx]
                resizeStartCorner = corners(b)[corner]
                resizeAnchor = corners(b)[3 - corner] // diagonal opposite
                return
            }
            state.selectedID = state.annotation(at: p)?.id
            moveLast = state.selectedID == nil ? nil : p
            didCheckpointMove = false
            needsDisplay = true
            return
        }
        if state.tool == .crop {
            cropStart = p
            cropRect = .zero
            needsDisplay = true
            return
        }
        if state.tool == .text {
            beginTextEditing(at: p)
            return
        }
        if state.tool == .step {
            // Single click drops the next-numbered badge.
            let n = state.annotations.filter { $0.kind == .step }.count + 1
            state.add(Annotation(kind: .step, points: [p], color: state.color,
                                 lineWidth: state.lineWidth, text: "\(n)"))
            needsDisplay = true
            return
        }
        draft = Annotation(kind: state.tool, points: [p], color: state.color, lineWidth: state.lineWidth)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        // Select tool: resize (if a handle is grabbed) or move.
        if state.tool == .select {
            if let orig = resizeOriginal, let anchor = resizeAnchor, let start = resizeStartCorner,
               let idx = state.selectedIndex {
                resizeAnnotation(at: idx, original: orig, anchor: anchor, start: start, to: p)
                needsDisplay = true
                return
            }
            guard let last = moveLast, let idx = state.selectedIndex else { return }
            if !didCheckpointMove { state.checkpoint(); didCheckpointMove = true }
            let delta = CGSize(width: p.x - last.x, height: p.y - last.y)
            state.annotations[idx] = state.annotations[idx].translated(by: delta)
            moveLast = p
            needsDisplay = true
            return
        }
        // Crop tool: rubber-band a crop rect.
        if state.tool == .crop, let s = cropStart {
            cropRect = CGRect(x: min(s.x, p.x), y: min(s.y, p.y),
                              width: abs(p.x - s.x), height: abs(p.y - s.y))
            needsDisplay = true
            return
        }

        guard var current = draft else { return }
        switch current.kind {
        case .pen, .marker:
            current.points.append(p)
        default: // two-point shapes track start→current
            if current.points.count < 2 { current.points.append(p) } else { current.points[1] = p }
        }
        draft = current
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if state.tool == .select {
            moveLast = nil
            resizeOriginal = nil; resizeAnchor = nil; resizeStartCorner = nil
            return
        }
        if state.tool == .crop {
            if let r = cropRect, r.width > 8, r.height > 8 { state.crop(to: r) }
            cropStart = nil; cropRect = nil
            needsDisplay = true
            return
        }
        guard let current = draft else { return }
        draft = nil
        // Ignore accidental taps that produced no real geometry.
        if current.points.count >= 2 { state.add(current) }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117: // Delete / Forward-delete removes the selected annotation
            if state.selectedID != nil { state.deleteSelected(); needsDisplay = true }
        case 53: // Esc: cancel text editing → deselect → close the editor
            if activeTextField != nil {
                commitTextEditing()
            } else if state.selectedID != nil {
                state.selectedID = nil; needsDisplay = true
            } else {
                state.onCancel?()
            }
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: Inline text

    private func beginTextEditing(at point: CGPoint) {
        commitTextEditing() // finish any prior field first

        let field = NSTextField(frame: CGRect(x: point.x, y: point.y, width: 220, height: state.fontHeight))
        field.font = .systemFont(ofSize: state.fontSize, weight: .semibold)
        field.textColor = state.color
        field.backgroundColor = .clear
        field.isBordered = false
        field.focusRingType = .none
        field.placeholderString = "Type…"
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        activeTextField = field
    }

    private func commitTextEditing() {
        guard let field = activeTextField else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let origin = field.frame.origin
        field.removeFromSuperview()
        activeTextField = nil
        guard !value.isEmpty else { return }
        state.add(Annotation(kind: .text, points: [origin], color: state.color,
                             lineWidth: state.lineWidth, text: value, fontSize: state.fontSize))
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitTextEditing()
    }
}
