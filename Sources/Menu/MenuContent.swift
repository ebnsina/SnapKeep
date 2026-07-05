import SwiftUI

/// The dropdown shown from the menu-bar icon: a header, a grid of every capture/record tool,
/// and a list of recent captures. Search is revealed on demand. Fully theme-aware.
struct MenuContent: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            header

            if app.isAuthorized {
                toolGrid
                recent
            } else {
                permissionPrompt
            }
        }
        .padding(Theme.Space.md)
        .frame(width: 340)
        .onAppear { app.library.reload() }
        .onExitCommand { dismiss() } // Esc closes the menu
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(Brand.name).font(.headline)
            Spacer()
            iconButton("gearshape") { dismiss(); app.openSettings() }
            iconButton("power") { NSApp.terminate(nil) }
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("Search recent captures", text: $search)
                .textFieldStyle(.plain).font(.system(size: 13)).focused($searchFocused)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.quaternary.opacity(0.6), in: Capsule())
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: Tools

    private var toolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ToolTile(title: "Region", symbol: "rectangle.dashed") { run { app.captureRegion() } }
            ToolTile(title: "Window", symbol: "macwindow") { run { app.captureWindow() } }
            ToolTile(title: "Full", symbol: "rectangle.inset.filled") { run { app.captureFullScreen() } }
            ToolTile(title: "Scroll", symbol: "arrow.down.doc") { run { app.scrollingCapture() } }
            ToolTile(title: app.recorder.isRecording ? "Stop" : "Record",
                     symbol: app.recorder.isRecording ? "stop.circle.fill" : "record.circle",
                     tint: .red) { run { app.toggleRecording() } }
            ToolTile(title: "Rec. Area", symbol: "rectangle.dashed.badge.record", tint: .red) { run { app.recordRegion() } }
            ToolTile(title: "Recapture", symbol: "arrow.clockwise") { run { app.recaptureLastRegion() } }
        }
    }

    private func run(_ action: () -> Void) { dismiss(); action() }

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
            iconButton("magnifyingglass", small: true, active: showSearch) {
                withAnimation(Theme.Motion.snappy) { showSearch.toggle() }
                if showSearch { searchFocused = true } else { search = "" }
            }
        }
        if showSearch { searchField }
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
                ForEach(items.prefix(6)) { RecentRow(item: $0) }
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

    private func iconButton(_ symbol: String, small: Bool = false, active: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: small ? 12 : 14))
                .frame(width: small ? 24 : 30, height: small ? 24 : 30)
                .foregroundStyle(active ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                .background(.quaternary.opacity(active ? 0.3 : 0.6), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tool tile

private struct ToolTile: View {
    let title: String
    let symbol: String
    var primary: Bool = false
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(primary ? AnyShapeStyle(Theme.accent)
                                      : AnyShapeStyle(.quaternary.opacity(hovering ? 1 : 0.55)))
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(primary ? AnyShapeStyle(.white) : AnyShapeStyle(tint ?? .primary))
                }
                .frame(height: 42)
                Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
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

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.ext)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Text(item.date, format: .relative(presentation: .named))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
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
