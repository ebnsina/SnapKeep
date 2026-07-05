import Carbon.HIToolbox
import AppKit

/// Registers system-wide hotkeys via Carbon `RegisterEventHotKey` — works whether or not
/// SnapKeep's menu is open, and needs no Accessibility permission (unlike a CGEvent tap).
@MainActor
final class HotKeyManager {
    private var refs: [EventHotKeyRef?] = []
    private var handlers: [HotKeyAction: () -> Void] = [:]
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
        applyBindings()
    }

    /// Re-register all hotkeys from the current settings (call after a rebind).
    func reload() { applyBindings() }

    private func applyBindings() {
        refs.forEach { if let r = $0 { UnregisterEventHotKey(r) } }
        refs.removeAll()
        for action in HotKeyAction.allCases {
            let b = AppSettings.shared.binding(for: action)
            add(action, keyCode: b.keyCode, modifiers: b.modifiers)
        }
    }

    private func installDispatcher() {
        guard eventHandler == nil else { return }
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
            if let action = HotKeyAction.allCases.first(where: { $0.carbonID == hkID.id }) {
                MainActor.assumeIsolated { manager.handlers[action]?() }
            }
            return noErr
        }, 1, &spec, this, &eventHandler)
    }

    private func add(_ action: HotKeyAction, keyCode: UInt32, modifiers: UInt32) {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: action.carbonID)
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
