import Carbon.HIToolbox
import AppKit

/// Registers system-wide hotkeys via Carbon `RegisterEventHotKey` — works whether or not
/// SnapKeep's menu is open, and needs no Accessibility permission (unlike a CGEvent tap).
@MainActor
final class HotKeyManager {
    /// Identifies each registered action so the dispatch handler can route key presses.
    enum Action: UInt32, CaseIterable {
        case region = 1
        case fullScreen = 2
        case window = 3
        case lastRegion = 4
        case record = 5
    }

    private var refs: [EventHotKeyRef?] = []
    private var handlers: [Action: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?

    /// The four-char signature Carbon uses to namespace our hotkey IDs.
    private let signature: OSType = 0x534E504B // 'SNPK'

    func register(region: @escaping () -> Void, fullScreen: @escaping () -> Void,
                  window: @escaping () -> Void, lastRegion: @escaping () -> Void,
                  record: @escaping () -> Void) {
        handlers[.region] = region
        handlers[.fullScreen] = fullScreen
        handlers[.window] = window
        handlers[.lastRegion] = lastRegion
        handlers[.record] = record

        installDispatcher()
        // ⌘⇧9 region, ⌘⇧4 full screen, ⌘⇧8 window, ⌘⇧7 recapture last, ⌘⇧6 record.
        add(.region, keyCode: UInt32(kVK_ANSI_9), modifiers: UInt32(cmdKey | shiftKey))
        add(.fullScreen, keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey))
        add(.window, keyCode: UInt32(kVK_ANSI_8), modifiers: UInt32(cmdKey | shiftKey))
        add(.lastRegion, keyCode: UInt32(kVK_ANSI_7), modifiers: UInt32(cmdKey | shiftKey))
        add(.record, keyCode: UInt32(kVK_ANSI_6), modifiers: UInt32(cmdKey | shiftKey))
    }

    private func installDispatcher() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let this = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            if let action = Action(rawValue: hkID.id) {
                MainActor.assumeIsolated { manager.handlers[action]?() }
            }
            return noErr
        }, 1, &spec, this, &eventHandler)
    }

    private func add(_ action: Action, keyCode: UInt32, modifiers: UInt32) {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: action.rawValue)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }

    func unregisterAll() {
        refs.forEach { if let r = $0 { UnregisterEventHotKey(r) } }
        refs.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }
}
