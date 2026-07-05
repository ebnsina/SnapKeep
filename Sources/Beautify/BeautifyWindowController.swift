import SwiftUI
import AppKit

/// Presents the Beautify view for a flattened capture in its own window.
@MainActor
final class BeautifyWindowController {
    private var window: NSWindow?
    var onClose: ((BeautifyWindowController) -> Void)?

    func present(image: NSImage) {
        let root = BeautifyView(source: image, onCopy: { img in
            CaptureStore.copyToClipboard(img)
        }, onSave: { img in
            _ = try? CaptureStore.save(img)
        }, onClose: { [weak self] in self?.close() })

        let win = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 720, height: 620),
                           styleMask: [.titled, .closable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "\(Brand.name) — Beautify"
        win.contentView = NSHostingView(rootView: root)
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    private func close() {
        window?.orderOut(nil)
        window = nil
        onClose?(self)
    }
}

struct BeautifyView: View {
    let source: NSImage
    let onCopy: (NSImage) -> Void
    let onSave: (NSImage) -> Void
    let onClose: () -> Void

    @State private var backdrop: BeautifyBackground = .ocean
    @State private var pad: CGFloat = 64
    @State private var radius: CGFloat = 14
    @State private var shadow = true

    var body: some View {
        VStack(spacing: 0) {
            preview
            Divider()
            controls
        }
        .frame(minWidth: 640, minHeight: 560)
        .onExitCommand { onClose() }
    }

    private var preview: some View {
        GeometryReader { geo in
            ZStack {
                gradientView
                Image(nsImage: source)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .shadow(color: shadow ? .black.opacity(0.35) : .clear, radius: 20, y: 10)
                    .padding(pad / 3)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black.opacity(0.2))
    }

    @ViewBuilder private var gradientView: some View {
        let colors = backdrop.colors.map { Color(nsColor: $0) }
        if colors.count == 2 {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            Color.clear
        }
    }

    private var controls: some View {
        VStack(spacing: Theme.Space.md) {
            HStack {
                ForEach(BeautifyBackground.allCases) { swatch($0) }
            }
            HStack(spacing: Theme.Space.lg) {
                labeledSlider("Padding", value: $pad, range: 0...160)
                labeledSlider("Radius", value: $radius, range: 0...40)
                Toggle("Shadow", isOn: $shadow).toggleStyle(.switch)
            }
            HStack {
                Spacer()
                Button("Copy") { onCopy(rendered()) }
                Button("Save") { onSave(rendered()); onClose() }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                Button("Close") { onClose() }
            }
        }
        .padding(Theme.Space.lg)
    }

    private func swatch(_ bg: BeautifyBackground) -> some View {
        let colors = bg.colors.map { Color(nsColor: $0) }
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(colors.count == 2
                  ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                  : AnyShapeStyle(.quaternary))
            .frame(width: 44, height: 30)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                backdrop == bg ? Theme.accent : Color.clear, lineWidth: 2.5))
            .overlay(bg == .none ? Text("—").font(.caption).foregroundStyle(.secondary) : nil)
            .onTapGesture { backdrop = bg }
    }

    private func labeledSlider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Slider(value: value, in: range)
        }
    }

    private func rendered() -> NSImage {
        BeautifyRenderer.render(image: source, background: backdrop,
                                padding: pad, cornerRadius: radius, shadow: shadow)
    }
}
