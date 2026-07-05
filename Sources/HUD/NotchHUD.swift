import SwiftUI
import AppKit

/// Observable content for the notch HUD.
@MainActor
@Observable
final class NotchHUDModel {
    var visible = false
    var icon = "checkmark.circle.fill"
    var title = ""
    var subtitle: String?
    var thumbnail: NSImage?
    var tint: Color = Theme.accent
    /// Bumped on every show so SwiftUI re-runs the insertion transition.
    var token = 0
}

/// A Dynamic-Island-style HUD that springs open from the top-center of the screen (under the
/// notch) for transient feedback — "Saved", "Copied", "Recording…", with an optional thumbnail.
@MainActor
final class NotchHUDController {
    static let shared = NotchHUDController()

    private let model = NotchHUDModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    private func ensurePanel() {
        guard panel == nil else { return }
        let width: CGFloat = 380, height: CGFloat = 120
        let p = NSPanel(contentRect: CGRect(x: 0, y: 0, width: width, height: height),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = NSHostingView(rootView: NotchHUDView(model: model))

        if let screen = NSScreen.main {
            let x = screen.frame.midX - width / 2
            // Anchor the top of the panel just under the top edge so it emerges from the notch.
            let y = screen.frame.maxY - height
            p.setFrameOrigin(CGPoint(x: x, y: y))
        }
        panel = p
    }

    /// Show the HUD with content, auto-dismissing after `seconds`.
    func show(icon: String, title: String, subtitle: String? = nil,
              thumbnail: NSImage? = nil, tint: Color = Theme.accent, seconds: Double = 2.0) {
        ensurePanel()
        panel?.orderFrontRegardless()

        model.icon = icon
        model.title = title
        model.subtitle = subtitle
        model.thumbnail = thumbnail
        model.tint = tint
        model.token += 1
        withAnimation(Theme.Motion.island) { model.visible = true }

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        withAnimation(Theme.Motion.smooth) { model.visible = false }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.panel?.orderOut(nil)
        }
    }
}

/// The pill that scales open from the top.
private struct NotchHUDView: View {
    @Bindable var model: NotchHUDModel

    var body: some View {
        VStack {
            if model.visible {
                pill
                    .id(model.token)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.15, anchor: .top).combined(with: .opacity),
                        removal: .scale(scale: 0.6, anchor: .top).combined(with: .opacity)
                    ))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
    }

    private var pill: some View {
        HStack(spacing: Theme.Space.md) {
            thumbnailOrIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(model.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                if let subtitle = model.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer(minLength: Theme.Space.sm)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 10)
        .frame(width: 300)
        .background(.black.opacity(0.85), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
    }

    @ViewBuilder private var thumbnailOrIcon: some View {
        if let thumb = model.thumbnail {
            Image(nsImage: thumb)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.2), lineWidth: 1))
        } else {
            Image(systemName: model.icon)
                .font(.system(size: 22))
                .foregroundStyle(model.tint)
                .frame(width: 34, height: 34)
        }
    }
}
