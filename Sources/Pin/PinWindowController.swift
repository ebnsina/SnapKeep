import AppKit

/// A capture pinned as a floating, always-on-top window — handy for referencing a shot
/// while you work. Draggable anywhere, with a close button on hover.
@MainActor
final class PinWindowController {
    var onClose: ((PinWindowController) -> Void)?
    private var window: NSWindow?

    private let image: NSImage

    init(image: NSImage) { self.image = image }

    func show() {
        // Cap the on-screen size while keeping aspect ratio.
        let maxSide: CGFloat = 480
        var size = image.size
        let factor = min(1, maxSide / max(size.width, size.height))
        size = CGSize(width: size.width * factor, height: size.height * factor)

        let win = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.level = .floating
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        win.contentView = PinContentView(image: image) { [weak self] in self?.close() }
        win.setFrameOrigin(CGPoint(x: 120, y: 120))
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
        onClose?(self)
    }
}

/// Rounded image with a hover close button.
private final class PinContentView: NSView {
    private let image: NSImage
    private let onClose: () -> Void
    private let closeButton = NSButton()
    private var hovering = false

    init(image: NSImage, onClose: @escaping () -> Void) {
        self.image = image
        self.onClose = onClose
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        closeButton.bezelStyle = .circular
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.isBordered = false
        closeButton.imageScaling = .scaleProportionallyUpOrDown
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.isHidden = true
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        closeButton.frame = CGRect(x: 6, y: bounds.height - 26, width: 20, height: 20)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; closeButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { hovering = false; closeButton.isHidden = true }

    @objc private func closeTapped() { onClose() }

    override func draw(_ dirtyRect: CGRect) {
        image.draw(in: bounds)
    }
}
