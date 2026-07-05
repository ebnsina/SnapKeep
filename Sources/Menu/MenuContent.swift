import SwiftUI

/// The dropdown shown from the menu-bar icon: a search field, a row of capture action tiles,
/// and a list of recent captures. Fully theme-aware (adapts to light/dark).
struct MenuContent: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            topBar

            if app.isAuthorized {
                actionTiles
                recent
            } else {
                permissionPrompt
            }
        }
        .padding(Theme.Space.md)
        .frame(width: 340)
        .onAppear { app.library.reload() }
    }

    // MARK: Top bar (search + settings)

    private var topBar: some View {
        HStack(spacing: Theme.Space.sm) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                TextField("Search captures", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.quaternary.opacity(0.6), in: Capsule())

            Button {
                dismiss(); app.openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
                    .background(.quaternary.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
    }

    // MARK: Action tiles

    private var actionTiles: some View {
        HStack(spacing: Theme.Space.xs) {
            ActionTile(title: "Region", symbol: "rectangle.dashed", primary: true) { dismiss(); app.captureRegion() }
            ActionTile(title: "Window", symbol: "macwindow") { dismiss(); app.captureWindow() }
            ActionTile(title: "Full", symbol: "rectangle.inset.filled") { dismiss(); app.captureFullScreen() }
            ActionTile(title: app.recorder.isRecording ? "Stop" : "Record",
                       symbol: app.recorder.isRecording ? "stop.circle.fill" : "record.circle",
                       tint: .red) { dismiss(); app.toggleRecording() }
            ActionTile(title: "Scroll", symbol: "arrow.down.doc") { dismiss(); app.scrollingCapture() }
        }
    }

    // MARK: Recent

    private var filtered: [CaptureItem] {
        let items = app.library.items
        guard !search.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    @ViewBuilder private var recent: some View {
        let items = filtered
        HStack {
            Text("Recent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.tertiary)
        }
        if items.isEmpty {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "photo.on.rectangle.angled").foregroundStyle(.tertiary)
                Text(search.isEmpty ? "Captures you save appear here." : "No matches.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, Theme.Space.sm)
        } else {
            VStack(spacing: 2) {
                ForEach(items.prefix(6)) { item in
                    RecentRow(item: item)
                }
            }
        }
    }

    // MARK: Permission

    private var permissionPrompt: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Label("Screen Recording permission needed", systemImage: "lock.shield")
                .font(.subheadline.weight(.medium))
            Text("Click Grant Access and allow \(Brand.name) in the macOS dialog, then Relaunch.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: Theme.Space.xs) {
                Button("Grant Access") { app.requestPermission() }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                Button("Relaunch") { app.relaunch() }
            }
        }
        .padding(Theme.Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}

// MARK: - Action tile

private struct ActionTile: View {
    let title: String
    let symbol: String
    var primary: Bool = false
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(primary ? AnyShapeStyle(Theme.accent)
                                      : AnyShapeStyle(.quaternary.opacity(hovering ? 1 : 0.6)))
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(primary ? AnyShapeStyle(.white)
                                                 : AnyShapeStyle(tint ?? .primary))
                }
                .frame(height: 44)
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
    }
}

// MARK: - Recent row

private struct RecentRow: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let item: CaptureItem
    @State private var hovering = false

    var body: some View {
        let thumb = app.library.thumbnail(for: item)
        HStack(spacing: Theme.Space.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.quaternary)
                if let thumb {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                if item.isVideo {
                    Image(systemName: "play.circle.fill").font(.system(size: 14)).foregroundStyle(.white).shadow(radius: 2)
                }
            }
            .frame(width: 46, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text(item.date, format: .relative(presentation: .named))
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Space.xs)

            if hovering {
                RowAction(symbol: item.isVideo ? "arrow.up.right.square" : "doc.on.doc",
                          help: item.isVideo ? "Open" : "Copy") {
                    dismiss(); item.isVideo ? app.open(item) : app.copyToClipboard(item)
                }
                RowAction(symbol: "folder", help: "Reveal") { app.reveal(item) }
                RowAction(symbol: "xmark", help: "Delete") { app.library.remove(item) }
            }
        }
        .padding(.vertical, 5).padding(.horizontal, 6)
        .background(hovering ? Color.primary.opacity(0.06) : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
        .onTapGesture {
            dismiss(); item.isVideo ? app.open(item) : app.copyToClipboard(item)
        }
        .draggable(item.url)
    }
}

private struct RowAction: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .foregroundStyle(hovering ? Color.primary : .secondary)
                .background(hovering ? Color.primary.opacity(0.1) : .clear, in: Circle())
        }
        .buttonStyle(.plain).help(help)
        .onHover { hovering = $0 }
    }
}
