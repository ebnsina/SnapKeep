import AppKit
import SwiftUI

/// Owns everything the post-capture editor needs: the base image, the annotation list,
/// the active tool/style, and undo/redo. The canvas and toolbar both bind to this.
@MainActor
@Observable
final class EditorState {
    private(set) var baseImage: CGImage
    /// On-screen size in points (pixels ÷ backing scale). Changes on crop/rotate.
    private(set) var displaySize: CGSize
    let scale: CGFloat

    /// Set by the controller so window + canvas resize when the geometry changes.
    @ObservationIgnored var onGeometryChange: (() -> Void)?
    /// Set by the controller; called when the user presses Esc with nothing to cancel.
    @ObservationIgnored var onCancel: (() -> Void)?

    var annotations: [Annotation] = []
    var tool: Annotation.Kind = .arrow
    var color: NSColor = NSColor(red: 0.95, green: 0.26, blue: 0.28, alpha: 1) // vivid red
    var lineWidth: CGFloat = 3
    var fontSize: CGFloat = 20
    var fontHeight: CGFloat { fontSize + 8 }

    /// Set by the canvas so model mutations (add/undo/redo) trigger a redraw.
    @ObservationIgnored var onChange: (() -> Void)?

    /// The currently selected annotation (Select tool).
    var selectedID: UUID?

    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    /// Palette offered in the toolbar.
    static let palette: [NSColor] = [
        NSColor(red: 0.95, green: 0.26, blue: 0.28, alpha: 1), // red
        NSColor(red: 0.99, green: 0.73, blue: 0.02, alpha: 1), // amber
        NSColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1), // green
        NSColor(red: 0.20, green: 0.53, blue: 0.98, alpha: 1), // blue
        NSColor(red: 0.55, green: 0.35, blue: 0.95, alpha: 1), // violet
        .white, .black
    ]

    init(cgImage: CGImage, scale: CGFloat) {
        self.baseImage = cgImage
        self.scale = scale
        self.displaySize = CGSize(width: CGFloat(cgImage.width) / scale,
                                  height: CGFloat(cgImage.height) / scale)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Snapshot the current state before a mutation so it can be undone.
    func checkpoint() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }

    func add(_ annotation: Annotation) {
        checkpoint()
        annotations.append(annotation)
        onChange?()
    }

    /// Add several annotations as one undoable step (used by Smart Redact).
    func addAll(_ list: [Annotation]) {
        guard !list.isEmpty else { return }
        checkpoint()
        annotations.append(contentsOf: list)
        onChange?()
    }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = prev
        onChange?()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        onChange?()
    }

    // MARK: Selection (Select tool)

    var selectedIndex: Int? {
        guard let id = selectedID else { return nil }
        return annotations.firstIndex { $0.id == id }
    }

    /// Topmost annotation whose padded bounds contain the point.
    func annotation(at point: CGPoint) -> Annotation? {
        annotations.last { $0.bounds.insetBy(dx: -8, dy: -8).contains(point) }
    }

    func deleteSelected() {
        guard let idx = selectedIndex else { return }
        checkpoint()
        annotations.remove(at: idx)
        selectedID = nil
        onChange?()
    }

    // MARK: Transforms (crop / rotate / flip)

    private func remap(_ transform: (CGPoint) -> CGPoint) {
        annotations = annotations.map { a in
            var copy = a
            copy.points = a.points.map(transform)
            return copy
        }
    }

    /// Rotate 90°. Point space is y-up, so a clockwise turn maps (x,y) → (y, W − x).
    func rotate(clockwise: Bool) {
        guard let rotated = ImageOps.rotate(baseImage, clockwise: clockwise) else { return }
        checkpoint()
        let W = displaySize.width, H = displaySize.height
        baseImage = rotated
        displaySize = CGSize(width: H, height: W)
        if clockwise { remap { CGPoint(x: $0.y, y: W - $0.x) } }
        else { remap { CGPoint(x: H - $0.y, y: $0.x) } }
        selectedID = nil
        onChange?(); onGeometryChange?()
    }

    func flipHorizontal() {
        guard let flipped = ImageOps.flipHorizontal(baseImage) else { return }
        checkpoint()
        let W = displaySize.width
        baseImage = flipped
        remap { CGPoint(x: W - $0.x, y: $0.y) }
        onChange?()
    }

    func flipVertical() {
        guard let flipped = ImageOps.flipVertical(baseImage) else { return }
        checkpoint()
        let H = displaySize.height
        baseImage = flipped
        remap { CGPoint(x: $0.x, y: H - $0.y) }
        onChange?()
    }

    /// Crop to a rect in point space (y-up, origin bottom-left).
    func crop(to rect: CGRect) {
        let r = rect.intersection(CGRect(origin: .zero, size: displaySize))
        guard r.width > 8, r.height > 8 else { return }
        // Point space (bottom-left) → base pixels (top-left).
        let px = CGRect(x: r.minX * scale, y: (displaySize.height - r.maxY) * scale,
                        width: r.width * scale, height: r.height * scale)
        guard let cropped = baseImage.cropping(to: px) else { return }
        checkpoint()
        baseImage = cropped
        displaySize = r.size
        remap { CGPoint(x: $0.x - r.minX, y: $0.y - r.minY) }
        selectedID = nil
        onChange?(); onGeometryChange?()
    }

    // MARK: Export

    /// Composite the base image with all annotations into a full-resolution NSImage.
    func flatten() -> NSImage {
        let pxW = baseImage.width, pxH = baseImage.height
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else {
            return NSImage(cgImage: baseImage, size: displaySize)
        }
        rep.size = displaySize
        guard let gctx = NSGraphicsContext(bitmapImageRep: rep) else {
            return NSImage(cgImage: baseImage, size: displaySize)
        }
        let ctx = gctx.cgContext
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gctx

        ctx.draw(baseImage, in: CGRect(x: 0, y: 0, width: pxW, height: pxH))
        // Annotations live in point space; scale up to pixel space to replay them.
        ctx.scaleBy(x: scale, y: scale)
        for annotation in annotations { annotation.render(in: ctx, base: baseImage, scale: scale) }

        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: displaySize)
        image.addRepresentation(rep)
        return image
    }
}
