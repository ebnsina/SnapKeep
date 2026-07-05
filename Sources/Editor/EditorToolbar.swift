import SwiftUI

/// The floating pill toolbar shown over the editor: tool picker, color, stroke, undo/redo,
/// and the copy/save/close actions.
struct EditorToolbar: View {
    @Bindable var state: EditorState
    let onCopy: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onCopyText: () -> Void
    let onBeautify: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            tools
            divider
            colors
            divider
            strokeControl
            divider
            historyControls
            divider
            actions
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }

    private var tools: some View {
        HStack(spacing: 2) {
            ForEach(Annotation.Kind.allCases) { kind in
                ToolButton(symbol: kind.symbol, help: kind.title,
                           isActive: state.tool == kind) {
                    state.tool = kind
                }
            }
        }
    }

    private var colors: some View {
        HStack(spacing: 5) {
            ForEach(Array(EditorState.palette.enumerated()), id: \.offset) { _, ns in
                let c = Color(nsColor: ns)
                Circle()
                    .fill(c)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.white.opacity(0.6),
                                                   lineWidth: state.color == ns ? 2 : 0.5))
                    .scaleEffect(state.color == ns ? 1.18 : 1)
                    .onTapGesture { state.color = ns }
                    .animation(Theme.Motion.snappy, value: state.color == ns)
            }
            ColorPicker("", selection: Binding(
                get: { Color(nsColor: state.color) },
                set: { state.color = NSColor($0) }
            ))
            .labelsHidden()
            .frame(width: 18)
        }
    }

    private var strokeControl: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "lineweight").font(.system(size: 11)).foregroundStyle(.secondary)
            Slider(value: $state.lineWidth, in: 1...12).frame(width: 70)
        }
    }

    private var historyControls: some View {
        HStack(spacing: 2) {
            ToolButton(symbol: "arrow.uturn.backward", help: "Undo", isActive: false,
                       disabled: !state.canUndo) { state.undo() }
            ToolButton(symbol: "arrow.uturn.forward", help: "Redo", isActive: false,
                       disabled: !state.canRedo) { state.redo() }
        }
    }

    private var actions: some View {
        HStack(spacing: Theme.Space.xs) {
            Button(action: onCopy) { Label("Copy", systemImage: "doc.on.doc") }
                .help("Copy to clipboard")
            Button(action: onCopyText) { Label("Copy Text", systemImage: "text.viewfinder") }
                .help("Extract text (OCR) and copy it")
            Button(action: onBeautify) { Label("Beautify", systemImage: "wand.and.stars") }
                .help("Add a gradient background, padding, and shadow")
            Button(action: onShare) { Label("Share", systemImage: "square.and.arrow.up") }
                .help("Share via AirDrop, Messages, Mail…")
            Button(action: onSave) { Label("Save", systemImage: "square.and.arrow.down") }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                .help("Save PNG")
            Button(action: onClose) { Image(systemName: "xmark") }
                .help("Close")
        }
        .labelStyle(.iconOnly)
        .controlSize(.large)
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 20)
    }
}

private struct ToolButton: View {
    let symbol: String
    let help: String
    let isActive: Bool
    var disabled: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 28)
                .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(isActive ? AnyShapeStyle(Theme.brandGradient)
                                     : AnyShapeStyle(hovering ? Color.primary.opacity(0.1) : .clear),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .help(help)
        .onHover { hovering = $0 }
        .animation(Theme.Motion.snappy, value: hovering)
        .animation(Theme.Motion.snappy, value: isActive)
    }
}
