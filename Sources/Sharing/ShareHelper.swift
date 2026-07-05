import AppKit

/// Native macOS sharing via `NSSharingServicePicker` — AirDrop, Messages, Mail, Notes,
/// and any share extension the user has installed. Entirely local; no SnapKeep backend.
@MainActor
enum ShareHelper {
    /// Present the system share sheet for one or more items, anchored to a view.
    static func present(items: [Any], from view: NSView, edge: NSRectEdge = .minY) {
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: edge)
    }

    /// Write an image to a temporary PNG so it can be shared with a real filename.
    static func temporaryPNG(for image: NSImage, name: String) -> URL? {
        guard let data = CaptureStore.pngData(from: image) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url); return url } catch { return nil }
    }
}
