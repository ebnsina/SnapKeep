import SwiftUI
import AppKit

/// A pill that shows a shortcut and, when clicked, records a new key combination.
struct KeyRecorderField: View {
    let binding: HotKeyBinding
    let onRecord: (HotKeyBinding) -> Void

    @State private var recording = false

    var body: some View {
        Button {
            recording.toggle()
        } label: {
            Text(recording ? "Press keys…" : binding.display)
                .font(.system(.body, design: .rounded).weight(.medium))
                .frame(minWidth: 64)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(recording ? AnyShapeStyle(Theme.accent.opacity(0.25))
                                      : AnyShapeStyle(.quaternary),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .strokeBorder(recording ? Theme.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .background(
            KeyCaptureView(isActive: recording) { captured in
                recording = false
                if let captured { onRecord(captured) }
            }
        )
    }
}

/// Invisible first-responder that captures the next key combination while active.
private struct KeyCaptureView: NSViewRepresentable {
    let isActive: Bool
    let onCapture: (HotKeyBinding?) -> Void

    func makeNSView(context: Context) -> CaptureNSView {
        let v = CaptureNSView()
        v.onCapture = onCapture
        return v
    }

    func updateNSView(_ nsView: CaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        if isActive {
            DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
        }
    }

    final class CaptureNSView: NSView {
        var onCapture: ((HotKeyBinding?) -> Void)?
        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { onCapture?(nil); return } // Esc cancels
            if let binding = HotKeyBinding.from(event: event) {
                onCapture?(binding)
            }
            // Otherwise (no modifier) ignore and keep listening.
        }

        override func resignFirstResponder() -> Bool {
            onCapture?(nil) // clicking away cancels
            return super.resignFirstResponder()
        }
    }
}
