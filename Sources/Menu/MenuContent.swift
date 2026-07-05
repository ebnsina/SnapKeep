import SwiftUI

/// The dropdown shown from the menu-bar icon. Modern, translucent, spring-animated.
struct MenuContent: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            header

            if app.isAuthorized {
                actions
            } else {
                permissionPrompt
            }

            Divider().opacity(0.4)

            footer
        }
        .padding(Theme.Space.md)
        .frame(width: 300)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.brandGradient)
            VStack(alignment: .leading, spacing: 0) {
                Text(Brand.name).font(.headline)
                Text(Brand.tagline)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.Space.xs) {
            MenuButton(title: "Capture Region", subtitle: "Drag to select · ⌘⇧5",
                       symbol: "rectangle.dashed.badge.record") {
                app.captureRegion()
            }
            .keyboardShortcut("5", modifiers: [.command, .shift])

            MenuButton(title: "Capture Full Screen", subtitle: "Copy & save · ⌘⇧4",
                       symbol: "rectangle.inset.filled") {
                app.captureFullScreen()
            }
            .keyboardShortcut("4", modifiers: [.command, .shift])

            if app.lastSavedURL != nil {
                MenuButton(title: "Reveal Last in Finder", subtitle: nil,
                           symbol: "folder") {
                    app.revealLastInFinder()
                }
            }
        }
    }

    private var permissionPrompt: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Label("Screen Recording permission needed", systemImage: "lock.shield")
                .font(.subheadline.weight(.medium))
            Text("\(Brand.name) can't capture the screen until you grant access in System Settings, then relaunch.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Grant Access…") { app.requestPermission() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    private var footer: some View {
        HStack {
            if let status = app.statusMessage {
                Text(status).font(.caption).foregroundStyle(Theme.accent)
                    .transition(.opacity)
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .animation(Theme.Motion.snappy, value: app.statusMessage)
    }
}

/// A rich, hover-highlighting menu row.
private struct MenuButton: View {
    let title: String
    let subtitle: String?
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                    .foregroundStyle(hovering ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.subheadline.weight(.medium))
                    if let subtitle {
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, Theme.Space.xs)
            .padding(.horizontal, Theme.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Theme.accent.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
    }
}
