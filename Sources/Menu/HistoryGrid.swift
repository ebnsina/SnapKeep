import SwiftUI

/// Recent captures shown in the menu-bar dropdown: a thumbnail grid. Click to copy,
/// right-click for Reveal / Share / Delete, and drag a thumbnail into any app.
struct HistoryGrid: View {
    @Environment(AppState.self) private var app

    private let columns = Array(repeating: GridItem(.fixed(84), spacing: Theme.Space.sm), count: 3)

    var body: some View {
        let items = app.library.items
        if items.isEmpty {
            EmptyHistory()
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Recent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: Theme.Space.sm) {
                    ForEach(items) { item in
                        HistoryCell(item: item)
                    }
                }
            }
        }
    }
}

private struct HistoryCell: View {
    @Environment(AppState.self) private var app
    let item: CaptureItem
    @State private var hovering = false

    var body: some View {
        let thumb = app.library.thumbnail(for: item)
        Group {
            if let thumb {
                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .frame(width: 84, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .strokeBorder(hovering ? Theme.accent : .white.opacity(0.1),
                              lineWidth: hovering ? 2 : 1)
        )
        .scaleEffect(hovering ? 1.04 : 1)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
        .onTapGesture { app.copyToClipboard(item) }
        .help("Click to copy · drag to any app")
        .draggable(item.url) {
            if let thumb { Image(nsImage: thumb).resizable().frame(width: 84, height: 60) }
        }
        .contextMenu {
            Button("Copy") { app.copyToClipboard(item) }
            Button("Pin to Desktop") { app.pin(item) }
            Button("Reveal in Finder") { app.reveal(item) }
            ShareLink("Share", item: item.url)
            Divider()
            Button("Delete", role: .destructive) { app.library.remove(item) }
        }
    }
}

private struct EmptyHistory: View {
    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 18)).foregroundStyle(.tertiary)
            Text("Captures you save will appear here.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, Theme.Space.xs)
    }
}
