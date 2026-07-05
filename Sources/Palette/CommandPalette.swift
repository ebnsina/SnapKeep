import SwiftUI
import AppKit

/// One runnable command in the palette.
struct Command: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let symbol: String
    let run: () -> Void
}

/// A Spotlight-style command palette: a centered floating panel with a search field and a
/// keyboard-navigable list of actions. Opened by a global hotkey.
@MainActor
final class CommandPaletteController {
    static let shared = CommandPaletteController()

    private var window: NSWindow?
    private var observer: NSObjectProtocol?

    func toggle(commands: [Command]) {
        if window != nil { close() } else { present(commands: commands) }
    }

    private func present(commands: [Command]) {
        let view = CommandPaletteView(commands: commands,
                                      onRun: { [weak self] cmd in self?.close(); cmd.run() },
                                      onClose: { [weak self] in self?.close() })
        let win = KeyableWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 420),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .modalPanel
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
        win.contentView = NSHostingView(rootView: view)

        if let screen = NSScreen.main {
            win.setFrameOrigin(CGPoint(x: screen.frame.midX - 280, y: screen.frame.midY - 100))
        }
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        // Close when it loses key focus (e.g. click outside).
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                          object: win, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        self.window = win
    }

    private func close() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        window?.orderOut(nil)
        window = nil
    }
}

/// Borderless windows can't become key by default; this allows typing in the search field.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - View

private struct CommandPaletteView: View {
    let commands: [Command]
    let onRun: (Command) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selected = 0

    private var filtered: [Command] {
        guard !query.isEmpty else { return commands }
        return commands.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PaletteField(text: $query,
                         onMove: { move($0) },
                         onEnter: { runSelected() },
                         onEsc: onClose)
                .frame(height: 30)
                .padding(.horizontal, Theme.Space.lg)
                .padding(.vertical, Theme.Space.md)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, cmd in
                            row(cmd, index: index)
                                .id(index)
                                .onTapGesture { onRun(cmd) }
                        }
                    }
                    .padding(Theme.Space.sm)
                }
                .onChange(of: selected) { _, new in
                    withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(new, anchor: .center) }
                }
            }
        }
        .frame(width: 560, height: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg).strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .onChange(of: query) { _, _ in selected = 0 }
    }

    private func row(_ cmd: Command, index: Int) -> some View {
        let isSel = index == selected
        return HStack(spacing: Theme.Space.md) {
            Image(systemName: cmd.symbol)
                .font(.system(size: 15))
                .frame(width: 24)
                .foregroundStyle(isSel ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            Text(cmd.title)
                .foregroundStyle(isSel ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            Spacer()
            if let sub = cmd.subtitle {
                Text(sub).font(.system(size: 12, design: .rounded))
                    .foregroundStyle(isSel ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, 9)
        .background(isSel ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .contentShape(Rectangle())
    }

    private func move(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selected = max(0, min(count - 1, selected + delta))
    }

    private func runSelected() {
        guard filtered.indices.contains(selected) else { return }
        onRun(filtered[selected])
    }
}

/// A search field that forwards arrow/enter/esc to the palette while typing.
private struct PaletteField: NSViewRepresentable {
    @Binding var text: String
    let onMove: (Int) -> Void
    let onEnter: () -> Void
    let onEsc: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "Run a command…"
        field.font = .systemFont(ofSize: 18, weight: .regular)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = context.coordinator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text { nsView.stringValue = text }
        if nsView.window?.firstResponder == nil {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: PaletteField
        init(_ parent: PaletteField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField { parent.text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1); return true
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1); return true
            case #selector(NSResponder.insertNewline(_:)): parent.onEnter(); return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onEsc(); return true
            default: return false
            }
        }
    }
}
