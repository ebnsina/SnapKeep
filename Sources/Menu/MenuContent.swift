import SwiftUI

/// The dropdown shown from the menu-bar icon. Modern, translucent, spring-animated.
struct MenuContent: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            header

            if app.isAuthorized {
                actions
                Divider().opacity(0.4)
                HistoryGrid()
            } else {
                permissionPrompt
            }

            Divider().opacity(0.4)

            footer
        }
        .padding(Theme.Space.md)
        .frame(width: 300)
        .onAppear { app.library.reload() }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.accent)
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
            MenuButton(title: "Capture Region", subtitle: "Drag to select · ⌘⇧9",
                       symbol: "rectangle.dashed.badge.record") {
                app.captureRegion()
            }
            .keyboardShortcut("9", modifiers: [.command, .shift])

            MenuButton(title: "Capture Window", subtitle: "Click a window · ⌘⇧8",
                       symbol: "macwindow") {
                app.captureWindow()
            }
            .keyboardShortcut("8", modifiers: [.command, .shift])

            MenuButton(title: "Scrolling Capture", subtitle: "Stitch a long page",
                       symbol: "arrow.down.doc") {
                app.scrollingCapture()
            }

            MenuButton(title: "Capture Full Screen", subtitle: "Copy & save · ⌘⇧4",
                       symbol: "rectangle.inset.filled") {
                app.captureFullScreen()
            }
            .keyboardShortcut("4", modifiers: [.command, .shift])

            MenuButton(title: "Recapture Last Region", subtitle: "Same area · ⌘⇧7",
                       symbol: "arrow.clockwise.circle") {
                app.recaptureLastRegion()
            }
            .keyboardShortcut("7", modifiers: [.command, .shift])

            MenuButton(title: app.recorder.isRecording ? "Stop Recording" : "Record Screen",
                       subtitle: app.recorder.isRecording ? "Recording… · ⌘⇧6" : "MP4 or GIF · ⌘⇧6",
                       symbol: app.recorder.isRecording ? "stop.circle.fill" : "record.circle") {
                app.toggleRecording()
            }
            .keyboardShortcut("6", modifiers: [.command, .shift])

            if !app.recorder.isRecording {
                MenuButton(title: "Record Region", subtitle: "Select an area to record",
                           symbol: "rectangle.dashed.badge.record") {
                    app.recordRegion()
                }
            }
        }
    }

    private var permissionPrompt: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Label("Screen Recording permission needed", systemImage: "lock.shield")
                .font(.subheadline.weight(.medium))
            Text("Click Grant Access and allow \(Brand.name) in the macOS dialog, then hit Relaunch to finish.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: Theme.Space.xs) {
                Button("Grant Access") { app.requestPermission() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                Button("Open Settings") { app.openScreenRecordingSettings() }
                Button("Relaunch") { app.relaunch() }
            }
            Text("Already allowed it? Just hit Relaunch.")
                .font(.caption2).foregroundStyle(.tertiary)
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
            Button {
                dismiss()
                app.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .animation(Theme.Motion.snappy, value: app.statusMessage)
    }
}

/// A rich, hover-highlighting menu row. Closes the menu after acting.
private struct MenuButton: View {
    let title: String
    let subtitle: String?
    let symbol: String
    let action: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var hovering = false

    var body: some View {
        Button {
            dismiss()
            action()
        } label: {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                    .foregroundStyle(hovering ? Color.primary : Color.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.subheadline.weight(.medium))
                    if let subtitle {
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, Theme.Space.sm)
            .padding(.horizontal, Theme.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Color.primary.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
    }
}
