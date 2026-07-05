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

    init(state: EditorState) {
        self.state = state
        super.init(frame: CGRect(origin: .zero, size: state.displaySize))
        // Redraw committed marks whenever the model changes (undo/redo/add).
        state.onChange = { [weak self] in self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    // MARK: Drawing

    override func draw(_ dirtyRect: CGRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.draw(state.baseImage, in: bounds) // scales pixels → points
        for annotation in state.annotations {
            annotation.render(in: ctx, base: state.baseImage, scale: state.scale)
        }
        draft?.render(in: ctx, base: state.baseImage, scale: state.scale)

        // Selection outline for the Select tool.
        if state.tool == .select, let idx = state.selectedIndex {
            let rect = state.annotations[idx].bounds.insetBy(dx: -4, dy: -4)
            ctx.setStrokeColor(Theme.accentNS.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [5, 3])
            ctx.stroke(rect)
            ctx.setLineDash(phase: 0, lengths: [])
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        if state.tool == .select {
            window?.makeFirstResponder(self) // so Delete removes the selection
            state.selectedID = state.annotation(at: p)?.id
            moveLast = state.selectedID == nil ? nil : p
            didCheckpointMove = false
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

        // Select tool: drag the selected annotation.
        if state.tool == .select {
            guard let last = moveLast, let idx = state.selectedIndex else { return }
            if !didCheckpointMove { state.checkpoint(); didCheckpointMove = true }
            let delta = CGSize(width: p.x - last.x, height: p.y - last.y)
            state.annotations[idx] = state.annotations[idx].translated(by: delta)
            moveLast = p
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
        if state.tool == .select { moveLast = nil; return }
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
