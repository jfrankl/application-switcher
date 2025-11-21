import AppKit
import SwiftUI

private struct ToastView: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .imageScale(.medium)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.7))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

/// A controller for the non-activating overlay panel and ephemeral toast panel.
/// Keeps window/panel setup concerns out of the core Switcher logic.
final class OverlayWindowController {
    private var window: NSWindow?
    private var hosting: NSHostingView<SwitchOverlayView>?
    private var screenObserver: Any?

    // Separate toast panel
    private var toastWindow: NSWindow?
    private var toastHosting: NSHostingView<ToastView>?
    private var toastHideWorkItem: DispatchWorkItem?

    // Selection callback provided by Switcher
    private var onSelect: ((NSRunningApplication) -> Void)?

    // Track the previously active app if you want to restore focus on cancel
    private var previouslyActiveApp: NSRunningApplication?

    // Track the width constraint so we can update it per screen size
    private var hostingMaxWidthConstraint: NSLayoutConstraint?

    init() {}

    func show(candidates: [NSRunningApplication], selectedIndex: Int?, searchText: String, showNumberBadges: Bool, onSelect: @escaping (NSRunningApplication) -> Void) {
        if window == nil {
            createWindow()
        }
        self.onSelect = onSelect

        previouslyActiveApp = NSWorkspace.shared.frontmostApplication

        window?.alphaValue = 1.0
        window?.isOpaque = false
        window?.isReleasedWhenClosed = false

        update(candidates: candidates, selectedIndex: selectedIndex, searchText: searchText, showNumberBadges: showNumberBadges)
        centerOnActiveScreen()

        window?.miniwindowTitle = ""
        window?.deminiaturize(nil)

        NSApp.activate(ignoringOtherApps: true)

        if let panel = window as? NSPanel {
            panel.orderFrontRegardless()
        } else {
            window?.orderFrontRegardless()
        }

        // Nudge level to ensure front-most ordering without stealing activation
        if let win = window {
            let currentLevel = win.level
            win.level = NSWindow.Level(rawValue: currentLevel.rawValue + 1)
            win.level = currentLevel
        }
    }

    func update(candidates: [NSRunningApplication], selectedIndex: Int?, searchText: String, showNumberBadges: Bool) {
        guard let hosting else { return }
        let view = SwitchOverlayView(
            candidates: candidates,
            selectedIndex: selectedIndex,
            searchText: searchText,
            showNumberBadges: showNumberBadges,
            onSelect: { [weak self] app in self?.onSelect?(app) }
        )
        hosting.rootView = view
        centerOnActiveScreen()
    }

    func showToast(_ text: String, duration: TimeInterval = 1.5) {
        if toastWindow == nil {
            createToastWindow()
        }

        toastHosting?.rootView = ToastView(text: text)

        positionToast()

        if let panel = toastWindow as? NSPanel {
            panel.orderFrontRegardless()
        } else {
            toastWindow?.orderFrontRegardless()
        }
        toastWindow?.alphaValue = 1.0

        toastHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hideToast(animated: true)
        }
        toastHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func hideToast(animated: Bool) {
        guard let toastWindow else { return }
        toastHideWorkItem?.cancel()
        toastHideWorkItem = nil

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                toastWindow.animator().alphaValue = 0
            } completionHandler: {
                toastWindow.orderOut(nil)
                toastWindow.alphaValue = 1.0
            }
        } else {
            toastWindow.orderOut(nil)
            toastWindow.alphaValue = 1.0
        }
    }

    func hide(animated: Bool = true) {
        guard let window else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                window.animator().alphaValue = 0
            } completionHandler: {
                DispatchQueue.main.async {
                    window.orderOut(nil)
                    window.alphaValue = 1.0
                }
            }
        } else {
            window.orderOut(nil)
            window.alphaValue = 1.0
        }
        hideToast(animated: false)
    }

    // MARK: - Window Setup

    private func createWindow() {
        let content = SwitchOverlayView(candidates: [], selectedIndex: nil, searchText: "", showNumberBadges: true, onSelect: { _ in })
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let win = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = false

        win.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary
        ]

        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true

        win.contentView = NSView()
        win.contentView?.wantsLayer = true
        win.contentView?.addSubview(hosting)

        let maxWidthConstraint = hosting.widthAnchor.constraint(lessThanOrEqualToConstant: 980)
        NSLayoutConstraint.activate([
            hosting.centerXAnchor.constraint(equalTo: win.contentView!.centerXAnchor),
            hosting.centerYAnchor.constraint(equalTo: win.contentView!.centerYAnchor),
            maxWidthConstraint
        ])

        self.window = win
        self.hosting = hosting
        self.hostingMaxWidthConstraint = maxWidthConstraint

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.centerOnActiveScreen()
            self?.positionToast()
        }

        centerOnActiveScreen()
    }

    private func createToastWindow() {
        let view = ToastView(text: "")
        let hosting = NSHostingView(rootView: view)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let win = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.level = .screenSaver
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true

        let container = NSView()
        container.wantsLayer = true
        win.contentView = container
        container.addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            hosting.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        self.toastWindow = win
        self.toastHosting = hosting
    }

    private func centerOnActiveScreen() {
        guard let win = window else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        // Compute the desired max width: visible frame minus 23px margins on each side.
        let visible = screen.visibleFrame
        let maxWidth = max(320, visible.width - 46)

        // Update the hosting width constraint to reflect current screen
        hostingMaxWidthConstraint?.constant = maxWidth

        let targetSize: NSSize
        if let hosting = hosting {
            let intrinsic = hosting.intrinsicContentSize
            let width = max(320, min(intrinsic.width > 0 ? intrinsic.width : 600, maxWidth))
            let height = max(120, intrinsic.height > 0 ? intrinsic.height : 200)
            targetSize = NSSize(width: width, height: height)
        } else {
            targetSize = NSSize(width: min(600, maxWidth), height: 200)
        }

        let x = visible.midX - targetSize.width / 2
        let y = visible.midY - targetSize.height / 2
        let frame = NSRect(x: x, y: y, width: targetSize.width, height: targetSize.height)

        win.setFrame(frame, display: true)
    }

    private func positionToast() {
        guard let toastWindow else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        // Measure current toast content size
        let size = toastHosting?.intrinsicContentSize ?? NSSize(width: 200, height: 36)
        let padding: CGFloat = 28
        let yOffset: CGFloat = 36 // distance from bottom edge

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - size.width / 2
        let y = screenFrame.minY + yOffset

        let frame = NSRect(x: x, y: y, width: size.width + padding, height: size.height + 8)
        toastWindow.setFrame(frame, display: true)
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }
}

// A non-activating, borderless panel that won’t steal focus.
private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing bufferingType: NSWindow.BackingStoreType, defer flag: Bool) {
        var mask = style
        mask.insert(.nonactivatingPanel)
        super.init(contentRect: contentRect, styleMask: mask, backing: bufferingType, defer: flag)
        isMovableByWindowBackground = false
        worksWhenModal = false
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        orderFrontRegardless()
    }

    override func makeKey() { }
}
