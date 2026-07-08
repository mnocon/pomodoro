import AppKit
import Carbon.HIToolbox

/// Registers the global ⌃⌥⌘P hotkey via Carbon's RegisterEventHotKey, which
/// works without Accessibility permission and from an unbundled binary
/// (unlike a CGEventTap).
final class HotkeyManager {
    var onHotkey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onHotkey?() }
            return noErr
        }, 1, &eventSpec, selfPtr, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x504D_4452) /* 'PMDR' */, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            UInt32(controlKey | optionKey | cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
