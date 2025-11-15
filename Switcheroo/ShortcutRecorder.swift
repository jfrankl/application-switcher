import SwiftUI
import AppKit

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> RecorderField {
        let v = RecorderField()
        v.coordinator = context.coordinator
        v.stringValue = shortcut.displayString
        return v
    }

    func updateNSView(_ nsView: RecorderField, context: Context) {
        nsView.stringValue = shortcut.displayString
    }

    final class Coordinator: NSObject {
        var parent: ShortcutRecorder
        init(_ parent: ShortcutRecorder) { self.parent = parent }

        func updateShortcut(_ new: Shortcut) {
            parent.shortcut = new
        }
    }
}

final class RecorderField: NSTextField {
    weak var coordinator: ShortcutRecorder.Coordinator?

    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isBezeled = true
        isBordered = true
        drawsBackground = true
        backgroundColor = NSColor.textBackgroundColor
        alignment = .center
        font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        placeholderString = "Click to record"
        focusRingType = .default
        lineBreakMode = .byTruncatingMiddle
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        placeholderString = "Recording… Press keys"
        stringValue = ""
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Capture keyCode and modifiers
        let keyCode = UInt32(event.keyCode)
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift, .capsLock, .function])

        let shortcut = Shortcut(keyCode: keyCode, modifiers: mods)
        coordinator?.updateShortcut(shortcut)

        // End recording on any key press
        isRecording = false
        placeholderString = "Click to record"
        stringValue = shortcut.displayString
        // Resign focus to avoid intercepting more keys
        window?.makeFirstResponder(nil)
    }

    override func flagsChanged(with event: NSEvent) {
        // Do not update on modifiers alone; commit when a keyDown arrives
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }
}
