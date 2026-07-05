import SwiftUI
import AppKit

/// First-run welcome window: introduces SnapKeep, lists shortcuts, and walks the user through
/// granting Screen Recording permission.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let app: AppState

    init(app: AppState) { self.app = app }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = OnboardingView(app: app, onFinish: { [weak self] in self?.close() })
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 660),
                           styleMask: [.titled, .closable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.contentView = NSHostingView(rootView: root)
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    private func close() {
        AppSettings.shared.hasCompletedOnboarding = true
        window?.close()
        window = nil
    }
}

private struct Feature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
}

private struct OnboardingView: View {
    @Bindable var app: AppState
    let onFinish: () -> Void

    private let features: [Feature] = [
        .init(icon: "rectangle.dashed", title: "Capture anything",
              subtitle: "Region, window, or full screen — plus scrolling capture for long pages"),
        .init(icon: "wand.and.stars", title: "Annotate & beautify",
              subtitle: "Arrows, text, steps, blur, crop, rotate, and gradient backdrops"),
        .init(icon: "record.circle", title: "Record",
              subtitle: "Screen or a region to MP4 or GIF, with optional system audio"),
        .init(icon: "lock.shield", title: "Private by design",
              subtitle: "On-device OCR, pin to desktop, history — no cloud, no accounts")
    ]

    var body: some View {
        VStack(spacing: 0) {
            hero
            VStack(spacing: Theme.Space.lg) {
                featureGrid
                Spacer(minLength: 0)
                permission
                Button(action: onFinish) {
                    Text("Get Started")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.Space.xl)
        }
        .frame(width: 600, height: 660)
        .background(.background)
    }

    private var hero: some View {
        VStack(spacing: Theme.Space.md) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.accent)
                .frame(width: 84, height: 84)
                .overlay(
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(.white)
                )
                .shadow(color: Theme.accent.opacity(0.35), radius: 14, y: 6)
            VStack(spacing: 4) {
                Text("Welcome to \(Brand.name)").font(.largeTitle.bold())
                Text("A fast, private screenshot and recording tool for macOS.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 44)
        .padding(.bottom, Theme.Space.xl)
        .background(
            Theme.accent.opacity(0.06)
                .overlay(alignment: .bottom) { Divider() }
        )
    }

    private var featureGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.md),
                            GridItem(.flexible(), spacing: Theme.Space.md)],
                  spacing: Theme.Space.md) {
            ForEach(features) { f in
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.accent.opacity(0.14))
                            .frame(width: 38, height: 38)
                        Image(systemName: f.icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(f.title).font(.headline)
                    Text(f.subtitle).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.md)
                .background(.quaternary.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .strokeBorder(.white.opacity(0.06), lineWidth: 1))
            }
        }
    }

    @ViewBuilder private var permission: some View {
        if app.isAuthorized {
            Label("Screen Recording permission granted", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.medium)).foregroundStyle(.green)
        } else {
            HStack(spacing: Theme.Space.md) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Screen Recording").font(.subheadline.weight(.semibold))
                    Text("Grant access, then relaunch to finish setup.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Grant") { app.requestPermission() }
                    .buttonStyle(.bordered).tint(Theme.accent)
                Button("Relaunch") { app.relaunch() }
                    .buttonStyle(.bordered)
            }
            .padding(Theme.Space.md)
            .frame(maxWidth: .infinity)
            .background(Theme.accent.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        }
    }
}
