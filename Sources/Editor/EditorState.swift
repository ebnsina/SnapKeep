import AppKit
import SwiftUI

/// Owns everything the post-capture editor needs: the base image, the annotation list,
/// the active tool/style, and undo/redo. The canvas and toolbar both bind to this.
@MainActor
@Observable
final class EditorState {
    let baseImage: CGImage
    /// On-screen size in points (pixels ÷ backing scale).
    let displaySize: CGSize
    let scale: CGFloat

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
