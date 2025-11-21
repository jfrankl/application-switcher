import SwiftUI
import AppKit
import Combine

// MARK: - Recording coordination

@MainActor
private final class RecordingCoordinator: ObservableObject {
    static let shared = RecordingCoordinator()

    // Track the currently active picker by its UUID
    private var activeID: UUID?

    // Ask to begin recording for a picker. If another is active, cancel it first.
    func begin(for picker: ShortcutPickerHandle) {
        if let current = activeID, current != picker.recorderID {
            // Tell the previous picker to cancel and revert
            NotificationCenter.default.post(name: .switcherooCancelOtherPicker, object: current)
        }
        activeID = picker.recorderID
        NotificationCenter.default.post(name: .switcherooBeginShortcutRecording, object: nil)
    }

    // End recording for picker if it is the active one.
    func end(for picker: ShortcutPickerHandle) {
        if activeID == picker.recorderID {
            activeID = nil
            NotificationCenter.default.post(name: .switcherooEndShortcutRecording, object: nil)
        }
    }

    // If a picker is going away while active, ensure we end the global state.
    func pickerDeinit(_ picker: ShortcutPickerHandle) {
        if activeID == picker.recorderID {
            activeID = nil
            NotificationCenter.default.post(name: .switcherooEndShortcutRecording, object: nil)
        }
    }
}

// A protocol implemented by ShortcutPicker so the coordinator can cancel/revert.
private protocol ShortcutPickerHandle {
    var recorderID: UUID { get }
    func cancelRecordingAndRevert()
}

// MARK: - Public SwiftUI control styled like the screenshot
struct ShortcutPicker: View, ShortcutPickerHandle {
    @Binding var shortcut: Shortcut

    // UI state
    @State private var isRecording = false
    @State private var liveModifiers: NSEvent.ModifierFlags = []

    // To revert on forced cancel
    @State private var snapshotBeforeRecording: Shortcut?

    // Hover/focus for styling
    @State private var hovered = false
    @FocusState private var focused: Bool

    // Make the ID stable across view re-instantiations
    @State private var _recorderID = UUID()
    private let coordinator = RecordingCoordinator.shared

    // Conformance: expose recorderID with proper access level
    fileprivate var recorderID: UUID { _recorderID }

    var body: some View {
        HStack(spacing: 8) {
            // Capsule button area
            Button {
                beginRecording()
            } label: {
                HStack(spacing: 6) {
                    Text(displayText())
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(foregroundColor)
                        .frame(minWidth: 120, alignment: .center)
                        .contentTransition(.opacity)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(capsuleBackground)
                .overlay(capsuleStroke)
            }
            .buttonStyle(.plain)
            .focusable(true)
            .focused($focused)
            .onHover { hovered = $0 }
            .accessibilityLabel("Shortcut")

            // Clear button
            Button {
                clearShortcut()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(Color(NSColor.controlAccentColor))
                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .help("Clear")
            .opacity(hasShortcut ? 1 : 0.35)
            .disabled(!hasShortcut)
        }
        .background(RecorderEventCatcher(
            isRecording: $isRecording,
            onCommit: { new in
                shortcut = new
                // Broadcast the committed shortcut so other pickers can clear if duplicate
                NotificationCenter.default.post(name: .switcherooShortcutCommitted, object: nil, userInfo: [
                    "shortcut": new,
                    "senderID": recorderID
                ])
                endRecording()
            },
            onCancel: {
                // Revert to snapshot if user cancels
                if let snap = snapshotBeforeRecording {
                    shortcut = snap
                }
                endRecording()
            }
        ))
        .onReceive(NotificationCenter.default.publisher(for: .switcherooCancelOtherPicker)) { note in
            guard let previousID = note.object as? UUID else { return }
            // If someone else started recording and we were the previous, cancel & revert.
            if previousID == self.recorderID {
                cancelRecordingAndRevert()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switcherooShortcutCommitted)) { note in
            guard
                let info = note.userInfo,
                let committed = info["shortcut"] as? Shortcut,
                let sender = info["senderID"] as? UUID
            else { return }
            // If another picker (different ID) committed the same shortcut, clear ours.
            if sender != self.recorderID, self.shortcutsEqual(committed, self.shortcut), self.hasShortcut {
                self.shortcut = self.noneShortcut
            }
        }
        .onDisappear {
            coordinator.pickerDeinit(self)
        }
    }

    // MARK: - ShortcutPickerHandle

    func cancelRecordingAndRevert() {
        if isRecording {
            if let snap = snapshotBeforeRecording {
                shortcut = snap
            }
            endRecording()
        }
    }

    // MARK: - State helpers

    // Treat keyCode==0 and empty modifiers as "no shortcut"
    private var noneShortcut: Shortcut { Shortcut(keyCode: 0, modifiers: []) }

    private func isNone(_ s: Shortcut) -> Bool {
        s.keyCode == 0 && s.modifiers.isEmpty
    }

    private func shortcutsEqual(_ a: Shortcut, _ b: Shortcut) -> Bool {
        a.keyCode == b.keyCode && a.modifiers == b.modifiers
    }

    private var hasShortcut: Bool {
        !isNone(shortcut)
    }

    private func clearShortcut() {
        shortcut = noneShortcut
    }

    private func beginRecording() {
        guard !isRecording else { return }
        snapshotBeforeRecording = shortcut
        isRecording = true
        focused = true
        RecordingCoordinator.shared.begin(for: self)
    }

    private func endRecording() {
        guard isRecording else { return }
        isRecording = false
        focused = false
        liveModifiers = []
        RecordingCoordinator.shared.end(for: self)
    }

    // MARK: - Styling

    private var isBlueFocused: Bool { isRecording }

    private var capsuleBackground: some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: isBlueFocused
                        ? [Color(NSColor.controlAccentColor).opacity(0.95),
                           Color(NSColor.controlAccentColor)]
                        : [
                            Color(nsColor: .windowBackgroundColor).opacity(0.55),
                            Color(nsColor: .windowBackgroundColor).opacity(0.75)
                          ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .shadow(color: Color.black.opacity(hovered || isBlueFocused ? 0.28 : 0.18),
                    radius: hovered || isBlueFocused ? 10 : 6, x: 0, y: 1)
    }

    private var capsuleStroke: some View {
        Capsule(style: .continuous)
            .stroke(isBlueFocused ? Color.white.opacity(0.35) : Color.white.opacity(0.12), lineWidth: 1)
    }

    private var foregroundColor: Color { isBlueFocused ? .white : .primary }

    private func displayText() -> String {
        if isRecording { return "•••" }
        if isNone(shortcut) { return " " }
        let s = shortcut.displayString.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? " " : s
    }
}

// MARK: - Invisible NSView that captures key events when recording

private struct RecorderEventCatcher: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCommit: (Shortcut) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> RecorderCatcherView {
        let v = RecorderCatcherView()
        v.handler = context.coordinator
        return v
    }

    func updateNSView(_ nsView: RecorderCatcherView, context: Context) {
        nsView.handler = context.coordinator
        nsView.isRecording = isRecording

        if isRecording, nsView.window?.firstResponder !== nsView {
            DispatchQueue.main.async { [weak nsView] in
                _ = nsView?.window?.makeFirstResponder(nsView)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, RecorderCatcherHandling {
        let parent: RecorderEventCatcher
        init(_ parent: RecorderEventCatcher) { self.parent = parent }

        func didCancel() { parent.onCancel() }

        func didCommit(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
            let shortcut = Shortcut(keyCode: UInt32(keyCode), modifiers: flags)
            parent.onCommit(shortcut)
        }
    }
}

private protocol RecorderCatcherHandling: AnyObject {
    func didCancel()
    func didCommit(keyCode: UInt16, flags: NSEvent.ModifierFlags)
}

private final class RecorderCatcherView: NSView {
    weak var handler: RecorderCatcherHandling?
    var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        // Esc cancels
        if event.keyCode == 53 {
            handler?.didCancel()
            return
        }
        // Always commit on any key while recording; allow duplicates
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift, .capsLock, .function])
        handler?.didCommit(keyCode: event.keyCode, flags: flags)
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            handler?.didCancel()
        } else {
            super.mouseDown(with: event)
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
}

private extension Color {
    init(nsColor: NSColor) { self.init(nsColor) }
}

private extension Notification.Name {
    static let switcherooBeginShortcutRecording = Notification.Name("SwitcherooBeginShortcutRecording")
    static let switcherooEndShortcutRecording   = Notification.Name("SwitcherooEndShortcutRecording")
    static let switcherooSuspendHotkeys         = Notification.Name("SwitcherooSuspendHotkeys")
    static let switcherooResumeHotkeys          = Notification.Name("SwitcherooResumeHotkeys")
    static let switcherooCancelOtherPicker      = Notification.Name("SwitcherooCancelOtherPicker")
    static let switcherooShortcutCommitted      = Notification.Name("SwitcherooShortcutCommitted")
}
