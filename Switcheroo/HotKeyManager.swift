import Cocoa
import Carbon

/// Carbon-based global hotkey manager supporting multiple IDs and callbacks.
/// Exposes a suppression hook (`shouldDeliverCallback`) used while recording shortcuts.
enum HotKeyEvent {
    case pressed
    case released
}

final class HotKeyManager {
    static let shared = HotKeyManager()
    private init() {
        installHandlerIfNeeded()
    }

    // FourCC 'SWCH'
    private let signature: OSType = 0x53574348

    // Multiple hotkeys support
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]              // id -> ref
    private var callbacks: [UInt32: (HotKeyEvent) -> Void] = [:]        // id -> callback
    private var handlerRef: EventHandlerRef?

    // Consult this before delivering callbacks. Return false to suppress delivery.
    var shouldDeliverCallback: (() -> Bool)?

    // Public: register or replace a hotkey for a given id
    func register(id: UInt32, shortcut: Shortcut, callback: @escaping (HotKeyEvent) -> Void) {
        // Unregister any existing hotkey with same id
        unregister(id: id)

        callbacks[id] = callback

        var hotKeyID = EventHotKeyID(signature: signature, id: id)

        let mods = carbonFlags(from: shortcut.modifiers)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, mods, hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        if status != noErr {
            NSLog("RegisterEventHotKey failed for id \(id): \(status)")
        } else if let ref {
            hotKeyRefs[id] = ref
        }

        installHandlerIfNeeded()
    }

    func unregister(id: UInt32) {
        if let ref = hotKeyRefs[id] {
            UnregisterEventHotKey(ref)
            hotKeyRefs.removeValue(forKey: id)
        }
        callbacks.removeValue(forKey: id)
    }

    func unregisterAll() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        callbacks.removeAll()

        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    deinit { unregisterAll() }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }

        let eventTypes: [EventTypeSpec] = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let status: OSStatus = eventTypes.withUnsafeBufferPointer { buffer in
            InstallEventHandler(
                GetEventDispatcherTarget(),
                hotKeyHandler,
                buffer.count,
                buffer.baseAddress,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                &handlerRef
            )
        }
        if status != noErr {
            NSLog("Failed to install hotkey handler: \(status)")
        }
    }

    private let hotKeyHandler: EventHandlerUPP = { (_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus in
        guard let userData, let event else { return noErr }
        let me = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

        // Suppress delivery if requested
        if let should = me.shouldDeliverCallback, should() == false {
            return noErr
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(event,
                                       EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID),
                                       nil,
                                       MemoryLayout<EventHotKeyID>.size,
                                       nil,
                                       &hotKeyID)
        guard status == noErr else { return noErr }

        let id = hotKeyID.id
        let kind = GetEventKind(event)

        if let cb = me.callbacks[id] {
            switch kind {
            case UInt32(kEventHotKeyPressed):
                cb(.pressed)
            case UInt32(kEventHotKeyReleased):
                cb(.released)
            default:
                break
            }
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
