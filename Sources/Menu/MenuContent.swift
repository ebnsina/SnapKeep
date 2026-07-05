import SwiftUI

/// The dropdown shown from the menu-bar icon: a header, the capture/record tools (as a tile
/// grid or a detailed list), and recent captures. Fully theme-aware.
struct MenuContent: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var showSearch = false
    @State private var gridMode = true
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: Theme.Space.md) {
            header

            if app.isAuthorized {
                if gridMode { toolGrid } else { toolList }
                recent
            } else {
                permissionPrompt
            }
        }
        .padding(Theme.Space.md)
        .frame(width: 340)
        .onAppear { app.library.reload() }
        .onExitCommand { dismiss() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(Brand.name).font(.headline)
            Spacer()
            iconButton(gridMode ? "list.bullet" : "square.grid.2x2",
                       label: gridMode ? "List view" : "Grid view") {
                withAnimation(Theme.Motion.snappy) { gridMode.toggle() }
            }
            iconButton("gearshape", label: "Settings") { dismiss(); app.openSettings() }
            iconButton("power", label: "Quit") { NSApp.terminate(nil) }
        }
    }

    // MARK: Tools

    private var tools: [ToolSpec] {
        func key(_ a: HotKeyAction) -> String? { AppSettings.shared.binding(for: a).display }
        return [
            ToolSpec(short: "Region", title: "Capture Region", symbol: "rectangle.dashed",
                     shortcut: key(.region)) { run { app.captureRegion() } },
            ToolSpec(short: "Window", title: "Capture Window", symbol: "macwindow",
                     shortcut: key(.window)) { run { app.captureWindow() } },
            ToolSpec(short: "Full", title: "Capture Full Screen", symbol: "rectangle.inset.filled",
                     shortcut: key(.fullScreen)) { run { app.captureFullScreen() } },
            ToolSpec(short: "Scroll", title: "Scrolling Capture", symbol: "arrow.down.doc",
                     shortcut: nil) { run { app.scrollingCapture() } },
            ToolSpec(short: app.recorder.isRecording ? "Stop" : "Record",
                     title: app.recorder.isRecording ? "Stop Recording" : "Record Screen",
                     symbol: app.recorder.isRecording ? "stop.circle.fill" : "record.circle",
                     tint: .red, shortcut: key(.record)) { run { app.toggleRecording() } },
            ToolSpec(short: "Rec. Area", title: "Record Region", symbol: "rectangle.dashed.badge.record",
                     tint: .red, shortcut: nil) { run { app.recordRegion() } },
            ToolSpec(short: "Recapture", title: "Recapture Last Region", symbol: "arrow.clockwise",
                     shortcut: key(.lastRegion)) { run { app.recaptureLastRegion() } }
        ]
    }

    private var toolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(tools) { t in
                ToolTile(title: t.short, symbol: t.symbol, tint: t.tint, action: t.action)
            }
        }
    }

    private var toolList: some View {
        VStack(spacing: 2) {
            ForEach(tools) { t in ToolRow(spec: t) }
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
        HStack(spacing: Theme.Space.xs) {
            Text("Recent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            iconButton("magnifyingglass", label: "Search", small: true, active: showSearch) {
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

    private func iconButton(_ symbol: String, label: String = "", small: Bool = false,
                            active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: small ? 12 : 14))
                .frame(width: small ? 24 : 30, height: small ? 24 : 30)
                .foregroundStyle(active ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                .background(.quaternary.opacity(active ? 0.3 : 0.6), in: Circle())
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

// MARK: - Tool model

private struct ToolSpec: Identifiable {
    let id = UUID()
    let short: String
    let title: String
    let symbol: String
    var tint: Color? = nil
    let shortcut: String?
    let action: () -> Void
}

// MARK: - Tool tile (grid)

private struct ToolTile: View {
    let title: String
    let symbol: String
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .fill(.quaternary.opacity(hovering ? 1 : 0.55))
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(tint ?? .primary)
                }
                .frame(height: 42)
                Text(title).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
        .accessibilityLabel(title)
    }
}

// MARK: - Tool row (list)

private struct ToolRow: View {
    let spec: ToolSpec
    @State private var hovering = false

    var body: some View {
        Button(action: spec.action) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: spec.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                    .foregroundStyle(spec.tint ?? (hovering ? Color.primary : .secondary))
                Text(spec.title).font(.subheadline.weight(.medium))
                Spacer()
                if let s = spec.shortcut {
                    Text(s).font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.vertical, 7).padding(.horizontal, Theme.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Color.primary.opacity(0.06) : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
            .contentShape(Rectangle())
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
                    Text(item.ext).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
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
        .onTapGesture { dismiss(); item.isVideo ? app.open(item) : app.copyToClipboard(item) }
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
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
        .onHover { hovering = $0 }
    }
}
