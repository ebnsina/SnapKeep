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
}

/// A Dynamic-Island-style HUD that drops from the top-center of the screen (under the notch)
/// for transient feedback. The pill is a single persistent view whose scale/offset/opacity are
/// animated — it never inserts or removes, so it can never render twice.
@MainActor
final class NotchHUDController {
    static let shared = NotchHUDController()

    private let model = NotchHUDModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var generation = 0

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
            // Anchor the panel's top to the bottom of the menu bar (visibleFrame excludes it),
            // so the pill sits BELOW the notch and is never split or clipped by it.
            let x = screen.frame.midX - width / 2
            let y = screen.visibleFrame.maxY - height
            p.setFrameOrigin(CGPoint(x: x, y: y))
        }
        panel = p
    }

    /// Show the HUD with content, auto-dismissing after `seconds`.
    func show(icon: String, title: String, subtitle: String? = nil,
              thumbnail: NSImage? = nil, tint: Color = Theme.accent, seconds: Double = 2.0) {
        ensurePanel()
        panel?.orderFrontRegardless()

        generation += 1
        model.icon = icon
        model.title = title
        model.subtitle = subtitle
        model.thumbnail = thumbnail
        model.tint = tint
        withAnimation(Theme.Motion.island) { model.visible = true }

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        let gen = generation
        withAnimation(Theme.Motion.smooth) { model.visible = false }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.generation == gen else { return }
            self.panel?.orderOut(nil)
        }
    }
}

/// The persistent pill. Hidden = tucked up into the notch (small, faded, offset up);
/// visible = settled just below. Only properties animate, never identity.
private struct NotchHUDView: View {
    @Bindable var model: NotchHUDModel

    var body: some View {
        VStack {
            pill
                .scaleEffect(model.visible ? 1 : 0.86, anchor: .top)
                .offset(y: model.visible ? 0 : -44)
                .opacity(model.visible ? 1 : 0)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 10)
        .allowsHitTesting(false)
    }

    private var pill: some View {
        HStack(spacing: Theme.Space.sm) {
            thumbnailOrIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let subtitle = model.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Space.sm)
        }
        .padding(.leading, 8)
        .padding(.trailing, Theme.Space.lg)
        .padding(.vertical, 8)
        .frame(width: 288, height: 52)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(.white.opacity(0.06))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
    }

    @ViewBuilder private var thumbnailOrIcon: some View {
        if let thumb = model.thumbnail {
            Image(nsImage: thumb)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.15), lineWidth: 1))
        } else {
            ZStack {
                Circle().fill(model.tint.opacity(0.18)).frame(width: 36, height: 36)
                Image(systemName: model.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(model.tint)
            }
        }
    }
}
