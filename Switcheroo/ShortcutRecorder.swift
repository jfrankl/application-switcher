import SwiftUI
import AppKit

// MARK: - Public SwiftUI control
struct ShortcutPicker: View {
    @Binding var shortcut: Shortcut
    @State private var isRecording = false
    @State private var pending: Shortcut?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            if isRecording {
                HStack(spacing: 6) {
                    ShortcutRecorderRepresentable(
                        current: pending ?? shortcut,
                        isRecording: true,
                        onCommit: { new in
                            shortcut = new
                            isRecording = false
                            pending = nil
                        },
                        onCancel: {
                            pending = nil
                            isRecording = false
                        },
                        onLiveUpdate: { live in
                            pending = live
                        }
                    )
                    .focused($focused)
                    .frame(height: 24)

                    Button {
                        pending = nil
                        isRecording = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                    .help("Cancel")
                }
                .onAppear { focused = true }
            } else {
                Button {
                    pending = nil
                    isRecording = true
                } label: {
                    HStack(spacing: 8) {
                        Text(displayText(for: shortcut))
                            .font(.system(size: 13, weight: .semibold))
                            .frame(minWidth: 120, alignment: .center)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private func displayText(for s: Shortcut) -> String {
        let str = s.displayString.trimmingCharacters(in: .whitespacesAndNewlines)
        return str.isEmpty ? "Set Shortcut…" : str
    }
}

// MARK: - NSViewRepresentable wrapper

struct ShortcutRecorderRepresentable: NSViewRepresentable {
    let current: Shortcut
    let isRecording: Bool
    let onCommit: (Shortcut) -> Void
    let onCancel: () -> Void
    let onLiveUpdate: (Shortcut) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> RecorderField {
        let v = RecorderField()
        v.coordinator = context.coordinator
        v.stringValue = current.displayString
        v.placeholderString = "Press keys…"
        return v
    }

    func updateNSView(_ nsView: RecorderField, context: Context) {
        nsView.coordinator = context.coordinator

        if isRecording {
            if nsView.isRecording == false {
                nsView.beginRecording()
            }
            nsView.stringValue = current.displayString
        } else {
            if nsView.isRecording == true {
                nsView.endRecording(cancel: true)
            } else {
                nsView.stringValue = current.displayString
            }
        }
    }

    final class Coordinator: NSObject {
        var parent: ShortcutRecorderRepresentable
        init(_ parent: ShortcutRecorderRepresentable) { self.parent = parent }

        func commit(_ new: Shortcut) { parent.onCommit(new) }
        func cancel() { parent.onCancel() }
        func liveUpdate(_ s: Shortcut) { parent.onLiveUpdate(s) }
    }
}

// MARK: - AppKit field

final class RecorderField: NSTextField {
    weak var coordinator: ShortcutRecorderRepresentable.Coordinator?

    fileprivate(set) var isRecording = false
    private var localMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isSelectable = false
        isBezeled = true
        isBordered = true
        drawsBackground = true
        backgroundColor = NSColor.textBackgroundColor
        alignment = .center
        font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        focusRingType = .default
        lineBreakMode = .byTruncatingMiddle
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        wantsLayer = true
        layer?.cornerRadius = 5
        placeholderString = "Press keys…"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
        stringValue = ""
        installClickOutsideMonitor()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            _ = self.window?.makeFirstResponder(self)
        }
    }

    func endRecording(cancel: Bool) {
        guard isRecording else { return }
        isRecording = false
        removeClickOutsideMonitor()
        if cancel {
            coordinator?.cancel()
        }
        DispatchQueue.main.async { [weak self] in
            _ = self?.window?.makeFirstResponder(nil)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if isRecording {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                _ = self.window?.makeFirstResponder(self)
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == 53 {
            endRecording(cancel: true)
            return
        }

        let keyCode = UInt32(event.keyCode)
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift, .capsLock, .function])

        let shortcut = Shortcut(keyCode: keyCode, modifiers: mods)
        coordinator?.commit(shortcut)

        endRecording(cancel: false)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return }
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift, .capsLock, .function])
        var parts: [String] = []
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option)  { parts.append("⌥") }
        if mods.contains(.shift)   { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        if mods.contains(.function){ parts.append("fn") }

        stringValue = parts.joined(separator: "") + " "
        coordinator?.liveUpdate(Shortcut(keyCode: 0, modifiers: mods))
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            endRecording(cancel: true)
        }
        return super.resignFirstResponder()
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let window = self.window else { return event }
            let locationInWindow = event.locationInWindow
            let locationInView = self.convert(locationInWindow, from: nil)
            let inside = self.bounds.insetBy(dx: -8, dy: -8).contains(locationInView)
            if !inside {
                self.endRecording(cancel: true)
            }
            return event
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}
