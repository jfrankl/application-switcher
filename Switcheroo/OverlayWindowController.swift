import AppKit
import SwiftUI

final class OverlayWindowController {
    private var window: NSWindow?
    private var hosting: NSHostingView<SwitchOverlayView>?
    private var screenObserver: Any?

    // Selection callback provided by Switcher
    private var onSelect: ((NSRunningApplication) -> Void)?

    init() {}

    func show(candidates: [NSRunningApplication], selectedIndex: Int?, searchText: String, onSelect: @escaping (NSRunningApplication) -> Void) {
        if window == nil {
            print("[Overlay] createWindow() (lazy)")
            createWindow()
        }
        self.onSelect = onSelect

        // Ensure sane state before showing
        window?.alphaValue = 1.0
        window?.isOpaque = false
        window?.isReleasedWhenClosed = false

        print("[Overlay] show() appActive=\(NSApp.isActive) candidates=\(candidates.count) selectedIndex=\(String(describing: selectedIndex))")
        update(candidates: candidates, selectedIndex: selectedIndex, searchText: searchText)

        // Re-center just before showing in case screens/spaces changed
        centerOnActiveScreen()

        // Make sure it’s not miniaturized and fully visible
        window?.miniwindowTitle = ""
        window?.deminiaturize(nil)

        // Order front above all regardless of app activation state
        if let panel = window as? NSPanel {
            panel.orderFrontRegardless()
        } else {
            window?.orderFrontRegardless()
        }

        // Force a re-raise to combat background stacking quirks
        if let win = window {
            let currentLevel = win.level
            win.level = NSWindow.Level(rawValue: currentLevel.rawValue + 1)
            win.level = currentLevel
        }

        print("[Overlay] show() ordered front. isVisible=\(window?.isVisible ?? false) alpha=\(window?.alphaValue ?? -1) level=\(window?.level.rawValue ?? -1)")
    }

    func update(candidates: [NSRunningApplication], selectedIndex: Int?, searchText: String) {
        guard let hosting else {
            print("[Overlay] update() skipped: hosting nil")
            return
        }
        let view = SwitchOverlayView(candidates: candidates, selectedIndex: selectedIndex, searchText: searchText, onSelect: { [weak self] app in
            self?.onSelect?(app)
        })
        hosting.rootView = view
        print("[Overlay] update() applied rootView. Intrinsic size = \(hosting.intrinsicContentSize)")
        centerOnActiveScreen()
    }

    func hide(animated: Bool = true) {
        guard let window else {
            print("[Overlay] hide() skipped: no window")
            return
        }
        if animated {
            print("[Overlay] hide(animated) begin")
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                window.animator().alphaValue = 0
            } completionHandler: {
                DispatchQueue.main.async {
                    window.orderOut(nil)
                    window.alphaValue = 1.0
                    print("[Overlay] hide(animated) completed. isVisible=\(window.isVisible)")
                }
            }
        } else {
            print("[Overlay] hide() immediate")
            window.orderOut(nil)
            window.alphaValue = 1.0
        }
    }

    private func createWindow() {
        let content = SwitchOverlayView(candidates: [], selectedIndex: nil, searchText: "", onSelect: { _ in })
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let win = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Maximum possible to ensure on-top visibility
        win.level = .screenSaver

        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.ignoresMouseEvents = false // allow clicking icons

        // Behaviors to appear across spaces/full-screen and remain stationary
        win.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary
        ]

        win.contentView = NSView()
        win.contentView?.wantsLayer = true
        win.contentView?.addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.centerXAnchor.constraint(equalTo: win.contentView!.centerXAnchor),
            hosting.centerYAnchor.constraint(equalTo: win.contentView!.centerYAnchor),
            hosting.widthAnchor.constraint(lessThanOrEqualToConstant: 980)
        ])

        self.window = win
        self.hosting = hosting

        print("[Overlay] createWindow() done. level=\(win.level.rawValue) ignoresMouse=\(win.ignoresMouseEvents) behaviors=\(win.collectionBehavior)")

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.centerOnActiveScreen()
        }

        centerOnActiveScreen()
    }

    private func centerOnActiveScreen() {
        guard let win = window else { return }
        let mainScreen = NSScreen.main
        let firstScreen = NSScreen.screens.first
        guard let screen = mainScreen ?? firstScreen else {
            print("[Overlay] centerOnActiveScreen(): no screens?")
            return
        }

        let targetSize: NSSize
        if let hosting = hosting {
            let intrinsic = hosting.intrinsicContentSize
            let width = max(320, min(intrinsic.width > 0 ? intrinsic.width : 600, 980))
            let height = max(120, intrinsic.height > 0 ? intrinsic.height : 200)
            targetSize = NSSize(width: width, height: height)
        } else {
            targetSize = NSSize(width: 600, height: 200)
        }

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - targetSize.width / 2
        let y = screenFrame.midY - targetSize.height / 2
        let frame = NSRect(x: x, y: y, width: targetSize.width, height: targetSize.height)

        win.setFrame(frame, display: true)
        print("[Overlay] centerOnActiveScreen() centered panel. windowFrame=\(win.frame)")
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        print("[Overlay] deinit")
    }
}

// A non-activating, borderless panel that won’t steal focus.
private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing bufferingType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
        isMovableByWindowBackground = false
        worksWhenModal = false
    }

    override func orderFront(_ sender: Any?) {
        super.orderFront(sender)
    }
}

