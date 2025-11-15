import Cocoa
import Carbon

enum HotKeyEvent {
    case pressed
    case released
}

final class HotKeyManager {
    static let shared = HotKeyManager()
    private init() {}

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var callback: ((HotKeyEvent) -> Void)?

    // FourCC 'SWCH'
    private let signature: OSType = 0x53574348

    func register(shortcut: Shortcut, callback: @escaping (HotKeyEvent) -> Void) {
        unregister()
        self.callback = callback

        var hotKeyID = EventHotKeyID(signature: signature, id: 1)

        let mods = carbonFlags(from: shortcut.modifiers)
        let status = RegisterEventHotKey(shortcut.keyCode, mods, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("RegisterEventHotKey failed: \(status)")
        }

        let eventTypes: [EventTypeSpec] = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let installStatus: OSStatus = eventTypes.withUnsafeBufferPointer { buffer in
            InstallEventHandler(
                GetEventDispatcherTarget(),
                hotKeyHandler,
                buffer.count,
                buffer.baseAddress,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                &handlerRef
            )
        }
        if installStatus != noErr {
            NSLog("Failed to install hotkey handler: \(installStatus)")
        }
    }

    func unregister() {
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        callback = nil
    }

    deinit { unregister() }

    private let hotKeyHandler: EventHandlerUPP = { (_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus in
        guard let userData, let event else { return noErr }
        let me = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        let kind = GetEventKind(event)

        switch kind {
        case UInt32(kEventHotKeyPressed):
            me.callback?(.pressed)
        case UInt32(kEventHotKeyReleased):
            me.callback?(.released)
        default:
            break
        }
        return noErr
    }

    // Map NSEvent.ModifierFlags -> Carbon modifiers
    private func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command)  { carbon |= UInt32(cmdKey) }
        if flags.contains(.option)   { carbon |= UInt32(optionKey) }
        if flags.contains(.control)  { carbon |= UInt32(controlKey) }
        if flags.contains(.shift)    { carbon |= UInt32(shiftKey) }
        if flags.contains(.function) { carbon |= UInt32(NX_SECONDARYFNMASK) }
        // capsLock intentionally ignored for global hotkeys
        return carbon
    }
}
