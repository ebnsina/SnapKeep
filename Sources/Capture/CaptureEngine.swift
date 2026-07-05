import ScreenCaptureKit
import AppKit

/// Errors surfaced by the capture pipeline.
enum CaptureError: LocalizedError {
    case notAuthorized
    case noDisplay
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "SnapKeep needs Screen Recording permission."
        case .noDisplay: return "No display was found to capture."
        case .captureFailed(let why): return "Capture failed: \(why)"
        }
    }
}

/// GPU-accelerated capture built on ScreenCaptureKit (macOS 14+ `SCScreenshotManager`).
/// Region and window capture layer on top of the same primitives in later milestones.
actor CaptureEngine {
    static let shared = CaptureEngine()

    /// Capture an entire display. Defaults to the display containing the mouse.
    func captureDisplay(_ display: SCDisplay? = nil) async throws -> NSImage {
        guard ScreenPermissions.isAuthorized else { throw CaptureError.notAuthorized }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let target = display ?? preferredDisplay(from: content) else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: target, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = target.width * scaleFactor(for: target)
        config.height = target.height * scaleFactor(for: target)
        config.showsCursor = false
        config.capturesAudio = false

        do {
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }
    }

    /// Crop a captured `CGImage` to a region (points), used by the region-select overlay.
    func crop(_ cgImage: CGImage, to rect: CGRect, scale: CGFloat) -> CGImage? {
        let scaled = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                            width: rect.width * scale, height: rect.height * scale)
        return cgImage.cropping(to: scaled)
    }

    // MARK: - Helpers

    private func preferredDisplay(from content: SCShareableContent) -> SCDisplay? {
        let mouse = NSEvent.mouseLocation
        // Match the SCDisplay whose frame contains the cursor; fall back to the first.
        for display in content.displays {
            let frame = CGRect(x: CGFloat(display.frame.origin.x), y: CGFloat(display.frame.origin.y),
                               width: CGFloat(display.width), height: CGFloat(display.height))
            if frame.contains(mouse) { return display }
        }
        return content.displays.first
    }

    private func scaleFactor(for display: SCDisplay) -> Int {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[.init("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
        }
        return Int(screen?.backingScaleFactor ?? 2)
    }
}
