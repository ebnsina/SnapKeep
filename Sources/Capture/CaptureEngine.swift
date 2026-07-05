import ScreenCaptureKit
import AppKit

/// Errors surfaced by the capture pipeline.
enum CaptureError: LocalizedError {
    case notAuthorized
    case noDisplay
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "\(Brand.name) needs Screen Recording permission."
        case .noDisplay: return "No display was found to capture."
        case .captureFailed(let why): return "Capture failed: \(why)"
        }
    }
}

/// GPU-accelerated capture built on ScreenCaptureKit (macOS 14+ `SCScreenshotManager`).
/// Region and window capture layer on top of the same primitives in later milestones.
actor CaptureEngine {
    static let shared = CaptureEngine()

    /// Touch ScreenCaptureKit once so macOS shows its native Screen Recording prompt and
    /// registers the app under its current signature. This is the reliable way to obtain
    /// the grant — far more so than `CGRequestScreenCaptureAccess`. Safe to call on launch.
    @discardableResult
    func primePermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    /// Capture an entire display. Defaults to the display containing the mouse.
    /// No preflight guard: calling ScreenCaptureKit is what triggers the OS prompt when
    /// permission is missing, and it simply throws if the user has denied it.
    func captureDisplay(_ display: SCDisplay? = nil) async throws -> NSImage {
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

    /// Capture a specific display (by ID) as a raw `CGImage` (native pixels). Used by the
    /// freeze-frame region overlay, which needs to crop precise pixels after selection.
    /// Takes Sendable primitives so callers don't send a non-Sendable `NSScreen` into the actor.
    func captureScreenImage(displayID: CGDirectDisplayID, scale: Int) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let target = content.displays.first(where: { $0.displayID == displayID })
                ?? content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: target, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = target.width * scale
        config.height = target.height * scale
        config.showsCursor = false
        config.capturesAudio = false

        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }
    }

    /// On-screen windows suitable for capture (excludes desktop/menubar chrome), with the
    /// data the picker overlay needs. Returned as Sendable tuples, newest/frontmost first.
    struct WindowInfo: Sendable {
        let id: CGWindowID
        let frame: CGRect      // global screen points
        let title: String
        let app: String
    }

    func listWindows() async throws -> [WindowInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        return content.windows.compactMap { w in
            guard w.isOnScreen, w.frame.width > 40, w.frame.height > 40 else { return nil }
            return WindowInfo(id: w.windowID, frame: w.frame,
                              title: w.title ?? "",
                              app: w.owningApplication?.applicationName ?? "")
        }
    }

    /// Capture a single window by ID at full resolution, with transparent corners.
    func captureWindow(id: CGWindowID, scale: Int) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw CaptureError.noDisplay
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width) * scale
        config.height = Int(window.frame.height) * scale
        config.showsCursor = false
        config.capturesAudio = false
        config.backgroundColor = .clear
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
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
