import AppKit

/// Drives the freeze-frame region capture flow:
/// capture the screen → show a full-screen overlay → let the user drag a selection →
/// crop the frozen pixels and return the result.
/// The cropped selection plus everything needed to map its pixels to points and to
/// recapture the exact same area later.
struct RegionCapture {
    let cgImage: CGImage
    let scale: CGFloat
    let displayID: CGDirectDisplayID
    /// Selection rectangle in native pixels within the source display.
    let pixelRect: CGRect
}

@MainActor
final class RegionCaptureController {
    private var window: NSWindow?
    private var continuation: CheckedContinuation<RegionCapture?, Never>?
    private var frozenCG: CGImage?
    private var targetScreen: NSScreen?

    /// Returns the cropped selection (with its scale), or nil if the user cancelled.
    func begin() async -> RegionCapture? {
        guard let screen = screenUnderCursor() else { return nil }
        targetScreen = screen

        let displayID = (screen.deviceDescription[.init("NSScreenNumber")] as? CGDirectDisplayID)
            ?? CGMainDisplayID()
        let scale = Int(screen.backingScaleFactor)

        let cg: CGImage
        do {
            cg = try await CaptureEngine.shared.captureScreenImage(displayID: displayID, scale: scale)
        } catch {
            NSLog("SnapKeep region capture failed: \(error.localizedDescription)")
            return nil
        }
        frozenCG = cg
        let frozen = NSImage(cgImage: cg, size: screen.frame.size)

        return await withCheckedContinuation { cont in
            self.continuation = cont
            presentOverlay(on: screen, frozen: frozen)
        }
    }

    private func presentOverlay(on screen: NSScreen, frozen: NSImage) {
        let win = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                           backing: .buffered, defer: false)
        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = .clear
        win.ignoresMouseEvents = false
        win.hasShadow = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = RegionSelectView(frame: CGRect(origin: .zero, size: screen.frame.size),
                                    frozen: frozen) { [weak self] rect in
            self?.finish(with: rect)
        }
        win.contentView = view
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    private func finish(with rect: CGRect?) {
        defer {
            window?.orderOut(nil)
            window = nil
        }
        guard let rect, let cg = frozenCG, let screen = targetScreen else {
            continuation?.resume(returning: nil)
            continuation = nil
            return
        }

        // View points (bottom-left origin) → image pixels (top-left origin).
        let scale = screen.backingScaleFactor
        let viewHeight = screen.frame.height
        let pixelRect = CGRect(x: rect.minX * scale,
                               y: (viewHeight - rect.maxY) * scale,
                               width: rect.width * scale,
                               height: rect.height * scale)

        guard let cropped = cg.cropping(to: pixelRect) else {
            continuation?.resume(returning: nil)
            continuation = nil
            return
        }
        let displayID = (screen.deviceDescription[.init("NSScreenNumber")] as? CGDirectDisplayID)
            ?? CGMainDisplayID()
        continuation?.resume(returning: RegionCapture(cgImage: cropped, scale: scale,
                                                      displayID: displayID, pixelRect: pixelRect))
        continuation = nil
    }

    private func screenUnderCursor() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }
}
