import AppKit
import AVFoundation

/// One saved capture on disk.
struct CaptureItem: Identifiable, Hashable {
    let id: URL          // the file URL doubles as a stable identity
    let date: Date
    var url: URL { id }
    var name: String { id.lastPathComponent }
    var isVideo: Bool { ["mp4", "mov"].contains(url.pathExtension.lowercased()) }
    var isAnimated: Bool { url.pathExtension.lowercased() == "gif" }
}

/// Tracks recently saved captures for the menu-bar history grid. Backed entirely by the
/// files already written to ~/Pictures/SnapKeep — no database, no network.
@MainActor
@Observable
final class CaptureLibrary {
    private(set) var items: [CaptureItem] = []
    private let maxItems = 24

    init() { reload() }

    /// Rebuild the list from disk (newest first).
    func reload() {
        let dir = CaptureStore.defaultDirectory
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []

        items = urls
            .filter { ["png", "jpg", "jpeg", "gif", "mp4", "mov"].contains($0.pathExtension.lowercased()) }
            .map { url -> CaptureItem in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return CaptureItem(id: url, date: date)
            }
            .sorted { $0.date > $1.date }
            .prefix(maxItems)
            .map { $0 }
    }

    /// Record a freshly saved file at the top of the list without a full disk rescan.
    func register(_ url: URL) {
        let item = CaptureItem(id: url, date: Date())
        items.removeAll { $0.id == url }
        items.insert(item, at: 0)
        if items.count > maxItems { items.removeLast(items.count - maxItems) }
    }

    /// Load a thumbnail-sized image for a capture (nil if the file vanished).
    func thumbnail(for item: CaptureItem, maxPixel: CGFloat = 320) -> NSImage? {
        if item.isVideo { return videoThumbnail(item.url) }
        guard let src = CGImageSourceCreateWithURL(item.url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func videoThumbnail(_ url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 0)
        guard let cg = try? generator.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600),
                                                  actualTime: nil) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    func remove(_ item: CaptureItem) {
        try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        items.removeAll { $0.id == item.id }
    }
}
