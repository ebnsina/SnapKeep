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
        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 620),
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

private struct OnboardingView: View {
    @Bindable var app: AppState
    let onFinish: () -> Void

    private let features: [(String, String, String)] = [
        ("rectangle.dashed", "Region & window capture", "Drag any area or click a window — ⌘⇧9 / ⌘⇧8"),
        ("pencil.tip.crop.circle", "Annotate", "Arrows, text, steps, blur, and more — then crop, rotate, beautify"),
        ("record.circle", "Record", "Screen or region to MP4 or GIF, with optional system audio — ⌘⇧6"),
        ("arrow.down.doc", "Scrolling capture", "Stitch a long page into one tall image"),
        ("text.viewfinder", "On-device OCR", "Grab text from any capture — 100% private")
    ]

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            header
            featureList
            Spacer(minLength: 0)
            permission
            Button(action: onFinish) {
                Text("Get Started").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.large)
        }
        .padding(Theme.Space.xl)
        .frame(width: 560, height: 620)
        .background(.background)
    }

    private var header: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 54)).foregroundStyle(Theme.brandGradient)
            Text("Welcome to \(Brand.name)").font(.largeTitle.bold())
            Text("A beautiful, private screenshot & recording tool for Apple Silicon.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Theme.Space.md)
    }

    private var featureList: some View {
        VStack(spacing: Theme.Space.sm) {
            ForEach(features, id: \.1) { icon, title, subtitle in
                HStack(spacing: Theme.Space.md) {
                    Image(systemName: icon)
                        .font(.system(size: 18)).foregroundStyle(Theme.accent)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.subheadline.weight(.semibold))
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, Theme.Space.xs)
                .padding(.horizontal, Theme.Space.md)
                .frame(maxWidth: .infinity)
                .background(.quaternary.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            }
        }
    }

    @ViewBuilder private var permission: some View {
        if app.isAuthorized {
            Label("Screen Recording permission granted", systemImage: "checkmark.seal.fill")
                .font(.subheadline).foregroundStyle(.green)
        } else {
            VStack(spacing: Theme.Space.xs) {
                Text("One step: grant Screen Recording so \(Brand.name) can capture.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Grant Access") { app.requestPermission() }
                        .buttonStyle(.bordered).tint(Theme.accent)
                    Button("Relaunch") { app.relaunch() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(Theme.Space.sm)
            .frame(maxWidth: .infinity)
            .background(Theme.accent.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
    }
}
