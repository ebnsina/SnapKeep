import SwiftUI

/// The floating toolbar over the editor: tools, color, stroke, undo/redo, and actions.
/// Every control shares one icon-button style for a consistent, polished look.
struct EditorToolbar: View {
    @Bindable var state: EditorState
    let onCopy: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onCopyText: () -> Void
    let onBeautify: () -> Void
    let onPrint: () -> Void
    let onRedact: () -> Void
    let onRemoveBg: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            tools
            divider
            colors
            divider
            stroke
            divider
            history
            divider
            actions
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
    }

    // MARK: Groups

    private var tools: some View {
        HStack(spacing: 3) {
            ForEach(Annotation.Kind.allCases) { kind in
                ToolbarIcon(symbol: kind.symbol, help: kind.title, isActive: state.tool == kind) {
                    state.tool = kind
                }
            }
        }
    }

    private var colors: some View {
        HStack(spacing: 6) {
            ForEach(Array(EditorState.palette.enumerated()), id: \.offset) { _, ns in
                Swatch(color: Color(nsColor: ns), selected: state.color == ns) {
                    state.color = ns
                }
            }
            CustomColorWell(color: Binding(
                get: { Color(nsColor: state.color) },
                set: { state.color = NSColor($0) }
            ))
        }
    }

    private var stroke: some View {
        HStack(spacing: 6) {
            Image(systemName: "lineweight")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Slider(value: $state.lineWidth, in: 1...12)
                .controlSize(.small)
                .frame(width: 78)
                .tint(Theme.accent)
        }
    }

    private var history: some View {
        HStack(spacing: 3) {
            ToolbarIcon(symbol: "arrow.uturn.backward", help: "Undo", disabled: !state.canUndo) { state.undo() }
            ToolbarIcon(symbol: "arrow.uturn.forward", help: "Redo", disabled: !state.canRedo) { state.redo() }
        }
    }

    private var actions: some View {
        HStack(spacing: 3) {
            ToolbarIcon(symbol: "doc.on.doc", help: "Copy to clipboard", action: onCopy)
            moreMenu
            ToolbarIcon(symbol: "square.and.arrow.down", help: "Save", role: .primary, action: onSave)
            ToolbarIcon(symbol: "xmark", help: "Close", action: onClose)
        }
    }

    /// Secondary actions tucked behind a "…" so the toolbar stays tidy.
    private var moreMenu: some View {
        Menu {
            Button { onCopyText() } label: { Label("Copy Text (OCR)", systemImage: "text.viewfinder") }
            Button { onRedact() } label: { Label("Redact Sensitive", systemImage: "eye.slash") }
            Button { onRemoveBg() } label: { Label("Remove Background", systemImage: "person.and.background.dotted") }
            Button { onBeautify() } label: { Label("Beautify", systemImage: "wand.and.stars") }
            Button { onShare() } label: { Label("Share…", systemImage: "square.and.arrow.up") }
            Button { onPrint() } label: { Label("Print…", systemImage: "printer") }
            Divider()
            Button { state.rotate(clockwise: false) } label: { Label("Rotate Left", systemImage: "rotate.left") }
            Button { state.rotate(clockwise: true) } label: { Label("Rotate Right", systemImage: "rotate.right") }
            Button { state.flipHorizontal() } label: { Label("Flip Horizontal", systemImage: "arrow.left.and.right") }
            Button { state.flipVertical() } label: { Label("Flip Vertical", systemImage: "arrow.up.and.down") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13.5, weight: .medium))
                .frame(width: 30, height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
    }

    private var divider: some View {
        Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 22)
    }
}

// MARK: - Reusable pieces

/// One uniform icon button. `.primary` fills with the brand color; active tools too.
private struct ToolbarIcon: View {
    enum Role { case normal, primary }

    let symbol: String
    var help: String = ""
    var isActive: Bool = false
    var disabled: Bool = false
    var role: Role = .normal
    let action: () -> Void

    @State private var hovering = false

    private var filled: Bool { isActive || role == .primary }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13.5, weight: .medium))
                .frame(width: 30, height: 28)
                .foregroundStyle(filled ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background {
                    let shape = RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    if filled {
                        shape.fill(Theme.accent)
                    } else if hovering {
                        shape.fill(.primary.opacity(0.1))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
        .help(help)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
        .animation(Theme.Motion.snappy, value: isActive)
    }
}

/// A color dot in the palette.
private struct Swatch: View {
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                .overlay(Circle().strokeBorder(Theme.accent, lineWidth: selected ? 2.5 : 0)
                    .padding(-2.5))
                .scaleEffect(selected ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.snappy, value: selected)
    }
}

/// Circular custom-color control: a rainbow ring that opens the system color panel.
/// A near-invisible ColorPicker sits on top so the tap target is the styled circle.
private struct CustomColorWell: View {
    @Binding var color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                      center: .center))
                .frame(width: 16, height: 16)
                .overlay(Circle().fill(color).frame(width: 8, height: 8))
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
            ColorPicker("", selection: $color)
                .labelsHidden()
                .opacity(0.02)
                .frame(width: 16, height: 16)
        }
        .help("Custom color")
    }
}
