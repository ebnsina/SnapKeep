import Carbon.HIToolbox
import AppKit

/// A stored global shortcut: a virtual key code plus Carbon modifier flags, with a display
/// string for the UI.
struct HotKeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon flags (cmdKey, shiftKey, …)
    var display: String

    /// Build from a captured NSEvent (converts Cocoa modifiers → Carbon).
    static func from(event: NSEvent) -> HotKeyBinding? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        var glyphs = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); glyphs += "⌃" }
        if flags.contains(.option)  { carbon |= UInt32(optionKey);  glyphs += "⌥" }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey);   glyphs += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey);     glyphs += "⌘" }
        guard carbon != 0 else { return nil } // require at least one modifier

        let key = keyName(for: event)
        guard !key.isEmpty else { return nil }
        return HotKeyBinding(keyCode: UInt32(event.keyCode), modifiers: carbon, display: glyphs + key)
    }

    private static func keyName(for event: NSEvent) -> String {
        // Named keys that have no printable character.
        let named: [Int: String] = [
            kVK_Return: "↩", kVK_Space: "Space", kVK_Tab: "⇥", kVK_Escape: "⎋",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
            kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
            kVK_F11: "F11", kVK_F12: "F12"
        ]
        if let n = named[Int(event.keyCode)] { return n }
        return (event.charactersIgnoringModifiers ?? "").uppercased()
    }
}

/// The capture actions that can be bound to a global shortcut.
enum HotKeyAction: String, CaseIterable, Identifiable {
    case region, fullScreen, window, lastRegion, record, palette
    var id: String { rawValue }

    var title: String {
        switch self {
        case .region: return "Capture region"
        case .fullScreen: return "Capture full screen"
        case .window: return "Capture window"
        case .lastRegion: return "Recapture last region"
        case .record: return "Record screen"
        case .palette: return "Command palette"
        }
    }

    /// Carbon-numbered event id used when registering the hotkey.
    var carbonID: UInt32 {
        switch self {
        case .region: return 1
        case .fullScreen: return 2
        case .window: return 3
        case .lastRegion: return 4
        case .record: return 5
        case .palette: return 6
        }
    }

    var defaultBinding: HotKeyBinding {
        let cmdShift = UInt32(cmdKey | shiftKey)
        switch self {
        case .region:     return .init(keyCode: UInt32(kVK_ANSI_9), modifiers: cmdShift, display: "⌘⇧9")
        case .fullScreen: return .init(keyCode: UInt32(kVK_ANSI_4), modifiers: cmdShift, display: "⌘⇧4")
        case .window:     return .init(keyCode: UInt32(kVK_ANSI_8), modifiers: cmdShift, display: "⌘⇧8")
        case .lastRegion: return .init(keyCode: UInt32(kVK_ANSI_7), modifiers: cmdShift, display: "⌘⇧7")
        case .record:     return .init(keyCode: UInt32(kVK_ANSI_6), modifiers: cmdShift, display: "⌘⇧6")
        case .palette:    return .init(keyCode: UInt32(kVK_ANSI_K), modifiers: cmdShift, display: "⌘⇧K")
        }
    }
}
