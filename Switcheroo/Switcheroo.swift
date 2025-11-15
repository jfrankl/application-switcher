import Cocoa
import SwiftUI
import Combine
import UserNotifications

@main
struct SwitcherooApp: App {
    @StateObject private var switcher = Switcher.shared
    private let statusBarController = StatusBarController()

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 16) {
                Text("Switcheroo")
                    .font(.system(size: 22, weight: .bold))

                Text("Press your shortcut to switch apps by MRU order.\nPress again to move to the next app.\nStop pressing for 2 seconds to select.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                // Shortcut configuration
                ShortcutSettingsView()

                Spacer()

                Text("Tip: If media keys adjust volume, enable “Use F1, F2, etc. keys as standard function keys” or hold Fn while pressing function keys.\nAccessibility permission may be requested for full control features.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(switcher.backgroundColor.ignoresSafeArea())
            .onAppear {
                DispatchQueue.main.async {
                    // Apply persisted dock icon preference
                    DockIconManager.shared.applyCurrentPreference()
                    statusBarController.installStatusItem()
                }
                Switcher.shared.start()
            }
        }
        .defaultSize(width: 520, height: 300)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)
    }
}

// MARK: - Dock Icon Manager

final class DockIconManager {
    static let shared = DockIconManager()
    private init() {}

    private let defaultsKey = "ShowDockIcon"

    var showDockIcon: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    func applyCurrentPreference() {
        setDockIconVisible(showDockIcon)
    }

    func toggle() {
        showDockIcon.toggle()
        setDockIconVisible(showDockIcon)
    }

    private func setDockIconVisible(_ visible: Bool) {
        let policy: NSApplication.ActivationPolicy = visible ? .regular : .accessory
        NSApplication.shared.setActivationPolicy(policy)

        if visible {
            NSApplication.shared.activate(ignoringOtherApps: false)
        }
    }
}

// MARK: - Status Bar

final class StatusBarController {
    private var statusItem: NSStatusItem?

    func installStatusItem() {
        if statusItem != nil { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let img = NSImage(systemSymbolName: "lightbulb", accessibilityDescription: "Switcheroo") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "Switcheroo"
            }
            button.toolTip = "Switcheroo"
        }
        let menu = NSMenu()

        let dockItem = NSMenuItem(title: dockMenuTitle(), action: #selector(toggleDockIcon), keyEquivalent: "")
        dockItem.target = self
        dockItem.state = DockIconManager.shared.showDockIcon ? .on : .off
        menu.addItem(dockItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit Switcheroo", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.last?.target = self

        item.menu = menu
        statusItem = item
    }

    @objc private func toggleDockIcon(_ sender: NSMenuItem) {
        DockIconManager.shared.toggle()
        sender.state = DockIconManager.shared.showDockIcon ? .on : .off
        sender.title = dockMenuTitle()
    }

    private func dockMenuTitle() -> String {
        DockIconManager.shared.showDockIcon ? "Hide Dock Icon" : "Show Dock Icon"
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Shortcut Settings UI

struct ShortcutSettingsView: View {
    @State private var current = Shortcut.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Global Shortcut")
                .font(.headline)
            HStack(spacing: 12) {
                ShortcutRecorder(shortcut: $current)
                    .frame(width: 180)
                Button("Save") {
                    current.save()
                    Switcher.shared.applyShortcut(current)
                }
                Button("Reset") {
                    current = .default
                    current.save()
                    Switcher.shared.applyShortcut(current)
                }
                Text("Current: \(current.displayString)")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            current = Shortcut.load()
        }
    }
}

// MARK: - Switcher Core

final class Switcher: ObservableObject {
    static let shared = Switcher()
    private init() {}

    @Published var backgroundColor: Color = Color(NSColor.windowBackgroundColor)

    private let longPressThreshold: TimeInterval = 1.0
    private var pressStart: Date?
    private var longPressTimer: DispatchSourceTimer?
    private var actionConsumedForThisPress = false

    private var systemMonitor: Any?

    private var activationObserver: Any?
    private var mru: [NSRunningApplication] = []

    private let overlay = OverlayWindowController()

    private var shortcut: Shortcut = .default

    // Type-to-select buffer and monitor
    private var searchBuffer: String = ""
    private var keyMonitor: Any?

    func start() {
        requestNotificationAuthorization()

        shortcut = Shortcut.load()
        applyShortcut(shortcut)

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.recordActivation(app)
        }

        seedMRU()
    }

    func applyShortcut(_ shortcut: Shortcut) {
        self.shortcut = shortcut
        HotKeyManager.shared.register(shortcut: shortcut) { [weak self] event in
            switch event {
            case .pressed:
                self?.onHotkeyPressed()
            case .released:
                self?.onHotkeyReleased()
            }
        }
    }

    private func onHotkeyPressed() {
        actionConsumedForThisPress = false
        pressStart = Date()

        cancelLongPressTimer()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + longPressThreshold)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.cancelLongPressTimer()
            if self.actionConsumedForThisPress == false {
                self.enterOverlayMode()
                self.actionConsumedForThisPress = true
            }
        }
        t.resume()
        longPressTimer = t
    }

    private func onHotkeyReleased() {
        let elapsed = pressStart.map { Date().timeIntervalSince($0) } ?? 0
        cancelLongPressTimer()
        pressStart = nil

        if actionConsumedForThisPress {
            actionConsumedForThisPress = false
            return
        }

        if elapsed < longPressThreshold {
            restorePreviousApp()
            actionConsumedForThisPress = true
        }
        actionConsumedForThisPress = false
    }

    private func cancelLongPressTimer() {
        longPressTimer?.cancel()
        longPressTimer = nil
    }

    private func restorePreviousApp() {
        postDebugNotification()
        updateBackgroundColor()
        pruneMRU()
        guard !mru.isEmpty else {
            NSLog("MRU empty; nothing to activate.")
            overlay.hide(animated: true)
            stopKeyMonitoring()
            return
        }
        let targetIndex = (mru.count > 1) ? 1 : 0
        let target = mru[targetIndex]
        activateApp(target)
        overlay.hide(animated: true)
        stopKeyMonitoring()
        clearSearchBuffer()
    }

    private func enterOverlayMode() {
        pruneMRU()
        if mru.isEmpty {
            overlay.hide(animated: true)
            stopKeyMonitoring()
            return
        }
        clearSearchBuffer()
        postOverlayEnteredNotification(candidateCount: mru.count)
        overlay.show(candidates: mru, selectedIndex: nil, searchText: searchBuffer, onSelect: { [weak self] app in
            guard let self else { return }
            self.activateApp(app)
            self.overlay.hide(animated: true)
            self.stopKeyMonitoring()
            self.clearSearchBuffer()
        })
        startKeyMonitoring()
    }

    private func seedMRU() {
        let running = NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                !app.isHidden &&
                !app.isTerminated
            }

        var list: [NSRunningApplication] = []
        if let front = running.first(where: { $0.isActive }) {
            list.append(front)
        }
        for app in running where !list.contains(where: { $0.processIdentifier == app.processIdentifier }) {
            list.append(app)
        }
        mru = list
        pruneMRU()
    }

    private func recordActivation(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular else { return }
        mru.removeAll { $0.processIdentifier == app.processIdentifier }
        mru.insert(app, at: 0)
        pruneMRU()
    }

    private func pruneMRU() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        mru = mru.filter { app in
            app.processIdentifier != myPID &&
            app.activationPolicy == .regular &&
            !app.isHidden &&
            !app.isTerminated
        }
    }

    private func activateApp(_ app: NSRunningApplication) {
        let name = app.localizedName ?? app.bundleIdentifier ?? "App"

        let optionSets: [[NSApplication.ActivationOptions]] = [
            [.activateIgnoringOtherApps],
            [.activateAllWindows, .activateIgnoringOtherApps],
            []
        ]

        for opts in optionSets {
            let ok: Bool
            if opts.isEmpty {
                ok = app.activate()
            } else {
                ok = app.activate(options: NSApplication.ActivationOptions(opts))
            }
            NSLog("Activating \(name) with options \(opts) -> \(ok ? "OK" : "Failed")")
            if ok { return }
        }

        if let url = app.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            config.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: url, configuration: config) { result, error in
                if result != nil {
                    NSLog("Reopen \(name) via NSWorkspace -> OK")
                } else {
                    NSLog("Reopen \(name) via NSWorkspace -> Failed (\(error?.localizedDescription ?? "unknown"))")
                    self.axUnhideAndRaise(app, appName: name)
                }
            }
            return
        }

        axUnhideAndRaise(app, appName: name)
    }

    // MARK: - Type-to-select

    private func startKeyMonitoring() {
        stopKeyMonitoring()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleOverlayKeyDown(event: event)
        }
    }

    private func stopKeyMonitoring() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleOverlayKeyDown(event: NSEvent) -> NSEvent? {
        // Allow arrow keys, tab, etc. to pass through if you later add selection navigation
        // For now, we consume only text entry keys and delete/escape/return
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            let scalar = chars.unicodeScalars.first!
            switch scalar {
            case "\u{7F}": // delete/backspace
                if !searchBuffer.isEmpty {
                    searchBuffer.removeLast()
                    updateOverlaySearchText()
                    tryUniqueMatch()
                }
                return nil
            case "\u{1B}": // escape
                if searchBuffer.isEmpty {
                    // Dismiss overlay if desired; for now just clear
                    overlay.hide(animated: true)
                    stopKeyMonitoring()
                }
                clearSearchBuffer()
                updateOverlaySearchText()
                return nil
            case "\r", "\n": // return/enter
                // If there is a single best match by prefix order, pick it
                if let match = bestMatch() {
                    activateApp(match)
                    overlay.hide(animated: true)
                    stopKeyMonitoring()
                    clearSearchBuffer()
                }
                return nil
            default:
                break
            }
        }

        // Accept alphanumeric and space
        if let chars = event.characters, chars.count == 1 {
            let c = chars.lowercased()
            if c.range(of: "^[a-z0-9 ]$", options: .regularExpression) != nil {
                searchBuffer.append(contentsOf: c)
                updateOverlaySearchText()
                tryUniqueMatch()
                return nil
            }
        }

        return event
    }

    private func clearSearchBuffer() {
        searchBuffer = ""
    }

    private func updateOverlaySearchText() {
        overlay.update(candidates: mru, selectedIndex: nil, searchText: searchBuffer)
    }

    private func normalizedName(for app: NSRunningApplication) -> String {
        let raw = app.localizedName ?? app.bundleIdentifier ?? ""
        return raw.lowercased()
    }

    private func bestMatch() -> NSRunningApplication? {
        let q = searchBuffer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return nil }
        let matches = mru.filter { normalizedName(for: $0).hasPrefix(q) }
        if matches.count == 1 { return matches.first }
        return nil
    }

    private func tryUniqueMatch() {
        if let app = bestMatch() {
            activateApp(app)
            overlay.hide(animated: true)
            stopKeyMonitoring()
            clearSearchBuffer()
        }
    }

    // MARK: - Missing helpers implemented

    private func requestNotificationAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("Notification authorization error: \(error.localizedDescription)")
            } else {
                NSLog("Notification authorization granted: \(granted)")
            }
        }
    }

    private func postDebugNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Switcheroo"
        content.body = "Quick switched to previous app."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("postDebugNotification failed: \(error.localizedDescription)")
            }
        }
    }

    private func postOverlayEnteredNotification(candidateCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Switcheroo"
        content.body = "Overlay shown with \(candidateCount) apps."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("postOverlayEnteredNotification failed: \(error.localizedDescription)")
            }
        }
    }

    private func updateBackgroundColor() {
        DispatchQueue.main.async {
            self.backgroundColor = Color(NSColor.windowBackgroundColor)
        }
    }

    private func axUnhideAndRaise(_ app: NSRunningApplication, appName: String) {
        let unhidden = app.unhide()
        let activated = app.activate(options: [.activateIgnoringOtherApps])
        NSLog("AX fallback for \(appName): unhide=\(unhidden) activate=\(activated)")
    }
}

