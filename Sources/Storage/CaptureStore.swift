import AppKit
import UniformTypeIdentifiers

/// Saves captures to disk and puts them on the clipboard. Fully local — no network.
enum CaptureStore {
    /// Where captures are written by default: ~/Pictures/<Brand>.
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent(Brand.saveFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Timestamped filename, e.g. `SnapKeep 2026-07-05 at 14.30.12.png`.
    static func suggestedName(ext: String = "png") -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(Brand.filePrefix) \(f.string(from: Date())).\(ext)"
    }

    @discardableResult
    static func savePNG(_ image: NSImage, to directory: URL? = nil) throws -> URL {
        guard let data = pngData(from: image) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let url = (directory ?? defaultDirectory).appendingPathComponent(suggestedName())
        try data.write(to: url)
        return url
    }

    /// Save honoring user settings (format + directory), and optionally play the shutter.
    @discardableResult
    @MainActor
    static func save(_ image: NSImage, settings: AppSettings = .shared) throws -> URL {
        let dir = settings.saveDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let format = settings.format
        let data: Data?
        switch format {
        case .png: data = pngData(from: image)
        case .jpeg: data = jpegData(from: image, quality: 0.9)
        }
        guard let data else { throw CocoaError(.fileWriteUnknown) }
        let url = dir.appendingPathComponent(suggestedName(ext: format.ext))
        try data.write(to: url)
        if settings.playSound { NSSound(named: "Grab")?.play() }
        return url
    }

    static func jpegData(from image: NSImage, quality: CGFloat) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    static func copyToClipboard(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
