import SwiftUI
import AppKit
import UserNotifications
import Combine

final class Switcher: ObservableObject {
    init() {
        self.longPressThreshold = Self.loadPersistedLongPressDelay()
        self.showNumberBadges = UserDefaults.standard.object(forKey: Self.numberBadgesDefaultsKey) as? Bool ?? true
        self.autoSelectSingleResult = UserDefaults.standard.object(forKey: Self.autoSelectDefaultsKey) as? Bool ?? true
        self.windowCycleShortcut = Self.loadWindowCycleShortcut()
        self.overlaySelectShortcut = Self.loadOverlaySelectShortcut()
        self.overlayQuitShortcut = Self.loadOverlayQuitShortcut()

        self.separateKeySwitchEnabled = UserDefaults.standard.object(forKey: Self.separateModeDefaultsKey) as? Bool ?? false
        self.separateToggleShortcut = Self.loadSeparateToggleShortcut()
        self.separateOverlayShortcut = Self.loadSeparateOverlayShortcut()

        HotKeyManager.shared.shouldDeliverCallback = { [weak self] in
            guard let self else { return true }
            return !self.hotkeysSuspended
        }
    }

    @Published var backgroundColor: Color = Color(NSColor.windowBackgroundColor)

    @Published private(set) var longPressThreshold: TimeInterval
    static let defaultLongPressDelay: TimeInterval = 1.0
    private static let longPressDefaultsKey = "LongPressDelay"

    @Published private(set) var showNumberBadges: Bool
    private static let numberBadgesDefaultsKey = "ShowNumberBadges"

    @Published private(set) var autoSelectSingleResult: Bool
    private static let autoSelectDefaultsKey = "AutoSelectSingleResult"

    @Published private(set) var separateKeySwitchEnabled: Bool
    private static let separateModeDefaultsKey = "SeparateKeySwitchEnabled"

    @Published private(set) var separateToggleShortcut: Shortcut
    @Published private(set) var separateOverlayShortcut: Shortcut

    @Published private(set) var hotkeysSuspended: Bool = false

    private static let separateToggleDefaultsKey = "SeparateToggleShortcut"
    private static let separateOverlayDefaultsKey = "SeparateOverlayShortcut"

    private static func loadSeparateToggleShortcut() -> Shortcut {
        if let data = UserDefaults.standard.data(forKey: separateToggleDefaultsKey),
           let s = try? JSONDecoder().decode(Shortcut.self, from: data) {
            return s
        }
        return Shortcut(keyCode: 111, modifiers: []) // F12
    }

    private static func saveSeparateToggleShortcut(_ s: Shortcut) {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: separateToggleDefaultsKey)
        }
    }

    private static func loadSeparateOverlayShortcut() -> Shortcut {
        if let data = UserDefaults.standard.data(forKey: separateOverlayDefaultsKey),
           let s = try? JSONDecoder().decode(Shortcut.self, from: data) {
            return s
        }
        return Shortcut(keyCode: 103, modifiers: []) // F11
    }

    private static func saveSeparateOverlayShortcut(_ s: Shortcut) {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: separateOverlayDefaultsKey)
        }
    }

    private var pressStart: Date?
    private var longPressTimer: DispatchSourceTimer?
    private var actionConsumedForThisPress = false

    private var activationObserver: Any?
    private var mru: [NSRunningApplication] = []

    private let overlay = OverlayWindowController()

    private var shortcut: Shortcut = .default

    @Published private(set) var windowCycleShortcut: Shortcut

    @Published private(set) var overlaySelectShortcut: Shortcut
    @Published private(set) var overlayQuitShortcut: Shortcut

    private var overlaySearchText: String = ""
    private var overlayFiltered: [NSRunningApplication] = []
    private var overlaySelectedIndex: Int? = nil
    private var overlayEventMonitor: Any?
    private var overlayGlobalEventMonitor: Any?

    private var overlayOriginApp: NSRunningApplication?

    private var overlayActivationObserver: Any?

    private var windowCycleStackByPID: [pid_t: [AppWindow]] = [:]
    private var windowCycleIndexByPID: [pid_t: Int] = [:]

    private var windowCycleLastStableIDByPID: [pid_t: Int] = [:]
    private var windowCycleLastIndexByPID: [pid_t: Int] = [:]

    private enum HotKeyID: UInt32 {
        case appSwitch = 1
        case windowCycle = 2
        case separateToggle = 3
        case separateOverlay = 4
    }

    func start() {
        requestNotificationAuthorization()

        shortcut = Shortcut.load()

        registerAllHotkeysForCurrentMode()

        Self.saveOverlaySelectShortcut(overlaySelectShortcut)
        Self.saveOverlayQuitShortcut(overlayQuitShortcut)

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.recordActivation(app)
            self.resetWindowCycleStacks(exceptPID: app.processIdentifier)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(onSuspendHotkeys), name: Notification.Name("SwitcherooSuspendHotkeys"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onResumeHotkeys), name: Notification.Name("SwitcherooResumeHotkeys"), object: nil)

        // New: fully disable global hotkeys while any picker is recording so the keystroke reaches the field
        NotificationCenter.default.addObserver(self, selector: #selector(beginShortcutRecording), name: Notification.Name("SwitcherooBeginShortcutRecording"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(endShortcutRecording), name: Notification.Name("SwitcherooEndShortcutRecording"), object: nil)

        seedMRU()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func beginShortcutRecording() {
        hotkeysSuspended = true
        HotKeyManager.shared.unregisterAll()
    }

    @objc private func endShortcutRecording() {
        hotkeysSuspended = false
        registerAllHotkeysForCurrentMode()
    }

    // Only allow callbacks from hotkeys that are active for the current mode.
    private func isHotKeyActive(id: UInt32) -> Bool {
        guard let hk = HotKeyID(rawValue: id) else { return false }
        switch hk {
        case .windowCycle:
            // Always active
            return true
        case .appSwitch:
            // Only in combined mode
            return !separateKeySwitchEnabled
        case .separateToggle, .separateOverlay:
            // Only in separate mode
            return separateKeySwitchEnabled
        }
    }

    // Centralized registration so duplicates are preserved and only active IDs act
    private func registerAllHotkeysForCurrentMode() {
        HotKeyManager.shared.unregisterAll()

        if separateKeySwitchEnabled {
            HotKeyManager.shared.register(id: HotKeyID.separateToggle.rawValue, shortcut: separateToggleShortcut) { [weak self] event in
                guard let self, self.isHotKeyActive(id: HotKeyID.separateToggle.rawValue) else { return }
                if case .pressed = event { self.onSeparateToggleTap() }
            }
            HotKeyManager.shared.register(id: HotKeyID.separateOverlay.rawValue, shortcut: separateOverlayShortcut) { [weak self] event in
                guard let self, self.isHotKeyActive(id: HotKeyID.separateOverlay.rawValue) else { return }
                if case .pressed = event { self.onSeparateOverlayTap() }
            }
        } else {
            HotKeyManager.shared.register(id: HotKeyID.appSwitch.rawValue, shortcut: shortcut) { [weak self] event in
                guard let self, self.isHotKeyActive(id: HotKeyID.appSwitch.rawValue) else { return }
                switch event {
                case .pressed: self.onHotkeyPressed()
                case .released: self.onHotkeyReleased()
                }
            }
        }

        HotKeyManager.shared.register(id: HotKeyID.windowCycle.rawValue, shortcut: windowCycleShortcut) { [weak self] event in
            guard let self, self.isHotKeyActive(id: HotKeyID.windowCycle.rawValue) else { return }
            switch event {
            case .pressed:
                self.postWindowCycleNotification()
                self.togglePreviousWindowInFrontmostApp()
            case .released:
                break
            }
        }
    }

    // Suspension control
    func suspendHotkeys() { hotkeysSuspended = true }
    func resumeHotkeys() { hotkeysSuspended = false }
    @objc private func onSuspendHotkeys() { suspendHotkeys() }
    @objc private func onResumeHotkeys() { resumeHotkeys() }

    // MARK: - Mode switching API

    func setSeparateKeySwitchEnabled(_ enabled: Bool) {
        guard enabled != separateKeySwitchEnabled else { return }
        separateKeySwitchEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.separateModeDefaultsKey)
        registerAllHotkeysForCurrentMode()
    }

    private func registerSeparateModeHotkeys() {
        registerAllHotkeysForCurrentMode()
    }

    func applySeparateToggleShortcut(_ s: Shortcut) {
        separateToggleShortcut = s
        Self.saveSeparateToggleShortcut(s)
        if separateKeySwitchEnabled { registerAllHotkeysForCurrentMode() }
    }

    func applySeparateOverlayShortcut(_ s: Shortcut) {
        separateOverlayShortcut = s
        Self.saveSeparateOverlayShortcut(s)
        if separateKeySwitchEnabled { registerAllHotkeysForCurrentMode() }
    }

    func applyAppSwitchShortcut(_ shortcut: Shortcut) {
        self.shortcut = shortcut
        if !separateKeySwitchEnabled { registerAllHotkeysForCurrentMode() }
    }

    func applyWindowCycleShortcut(_ shortcut: Shortcut) {
        windowCycleShortcut = shortcut
        Self.saveWindowCycleShortcut(shortcut)
        registerAllHotkeysForCurrentMode()
    }

    func applyOverlaySelectShortcut(_ s: Shortcut) {
        overlaySelectShortcut = s
        Self.saveOverlaySelectShortcut(s)
    }

    func applyOverlayQuitShortcut(_ s: Shortcut) {
        overlayQuitShortcut = s
        Self.saveOverlayQuitShortcut(s)
    }

    func applyLongPressDelay(_ value: TimeInterval) {
        let clamped = max(0.05, min(5.0, value))
        guard clamped != longPressThreshold else { return }
        longPressThreshold = clamped
        UserDefaults.standard.set(clamped, forKey: Self.longPressDefaultsKey)

        if pressStart != nil && !separateKeySwitchEnabled {
            rescheduleLongPressTimer()
        }
    }

    func setShowNumberBadges(_ show: Bool) {
        guard show != showNumberBadges else { return }
        showNumberBadges = show
        UserDefaults.standard.set(show, forKey: Self.numberBadgesDefaultsKey)
        overlay.update(candidates: overlayFiltered, selectedIndex: overlaySelectedIndex, searchText: overlaySearchText, showNumberBadges: showNumberBadges)
    }

    func setAutoSelectSingleResult(_ enabled: Bool) {
        guard enabled != autoSelectSingleResult else { return }
        autoSelectSingleResult = enabled
        UserDefaults.standard.set(enabled, forKey: Self.autoSelectDefaultsKey)
    }

    private static func loadPersistedLongPressDelay() -> TimeInterval {
        let v = UserDefaults.standard.double(forKey: longPressDefaultsKey)
        if v == 0 { return defaultLongPressDelay }
        return max(0.05, min(5.0, v))
    }

    private static let windowCycleDefaultsKey = "WindowCycleShortcut"

    private static func loadWindowCycleShortcut() -> Shortcut {
        if let data = UserDefaults.standard.data(forKey: windowCycleDefaultsKey),
           let s = try? JSONDecoder().decode(Shortcut.self, from: data) {
            return s
        }
        return Shortcut(keyCode: 103, modifiers: [])
    }

    private static func saveWindowCycleShortcut(_ s: Shortcut) {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: windowCycleDefaultsKey)
        }
    }

    private static let overlaySelectDefaultsKey = "OverlaySelectShortcut"
    private static let overlayQuitDefaultsKey = "OverlayQuitShortcut"

    private static var defaultOverlaySelect: Shortcut { Shortcut(keyCode: 36, modifiers: []) }
    private static var defaultOverlayQuit: Shortcut { Shortcut(keyCode: 12, modifiers: [.command]) }

    private static func loadOverlaySelectShortcut() -> Shortcut {
        if let data = UserDefaults.standard.data(forKey: overlaySelectDefaultsKey),
           let s = try? JSONDecoder().decode(Shortcut.self, from: data) {
            return s
        }
        return defaultOverlaySelect
    }

    private static func saveOverlaySelectShortcut(_ s: Shortcut) {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: overlaySelectDefaultsKey)
        }
    }

    private static func loadOverlayQuitShortcut() -> Shortcut {
        if let data = UserDefaults.standard.data(forKey: overlayQuitDefaultsKey),
           let s = try? JSONDecoder().decode(Shortcut.self, from: data) {
            return s
        }
        return defaultOverlayQuit
    }

    private static func saveOverlayQuitShortcut(_ s: Shortcut) -> Void {
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: overlayQuitDefaultsKey)
        }
    }

    private func overlayIsVisible() -> Bool {
        overlayEventMonitor != nil || overlayGlobalEventMonitor != nil
    }

    // MARK: - Combined mode (press/hold)

    private func onHotkeyPressed() {
        guard !separateKeySwitchEnabled else { return }
        if overlayIsVisible() {
            actionConsumedForThisPress = false
            pressStart = Date()

            cancelLongPressTimer()
            let t = DispatchSource.makeTimerSource(queue: .main)
            t.schedule(deadline: .now() + longPressThreshold)
            t.setEventHandler { [weak self] in
                guard let self else { return }
                self.cancelLongPressTimer()
                if self.actionConsumedForThisPress == false {
                    self.hideOverlayAndCleanup(reactivateOrigin: true)
                    self.actionConsumedForThisPress = true
                }
            }
            t.resume()
            longPressTimer = t
            return
        }

        actionConsumedForThisPress = false
        pressStart = Date()
        cancelLongPressTimer()
        scheduleLongPressTimer()
    }

    private func scheduleLongPressTimer() {
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

    private func rescheduleLongPressTimer() {
        cancelLongPressTimer()
        scheduleLongPressTimer()
    }

    private func onHotkeyReleased() {
        guard !separateKeySwitchEnabled else { return }
        let elapsed = pressStart.map { Date().timeIntervalSince($0) } ?? 0
        cancelLongPressTimer()
        pressStart = nil

        if actionConsumedForThisPress {
            actionConsumedForThisPress = false
            return
        }

        if overlayIsVisible(), elapsed < longPressThreshold {
            moveSelection(delta: 1)
            actionConsumedForThisPress = true
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

    // MARK: - Separate mode tap handlers

    private func onSeparateToggleTap() {
        restorePreviousApp()
    }

    private func onSeparateOverlayTap() {
        if overlayIsVisible() {
            moveSelection(delta: 1)
        } else {
            enterOverlayMode()
        }
    }

    private func hideOverlayAndCleanup(reactivateOrigin: Bool) {
        overlay.hide(animated: true)
        removeOverlayEventMonitor()
        removeOverlayActivationObserver()
        if reactivateOrigin, let origin = overlayOriginApp {
            _ = origin.activate(options: [])
        }
        overlayOriginApp = nil
    }

    private func restorePreviousApp() {
        postDebugNotification()
        pruneMRU()
        guard !mru.isEmpty else {
            NSLog("MRU empty; nothing to activate.")
            hideOverlayAndCleanup(reactivateOrigin: false)
            return
        }
        let targetIndex = (mru.count > 1) ? 1 : 0
        let target = mru[targetIndex]
        activateApp(target)
        hideOverlayAndCleanup(reactivateOrigin: false)
    }

    private func enterOverlayMode() {
        pruneMRU()
        if mru.isEmpty {
            hideOverlayAndCleanup(reactivateOrigin: false)
            return
        }
        overlaySearchText = ""
        overlayFiltered = mru
        overlaySelectedIndex = overlayFiltered.isEmpty ? nil : 0

        overlayOriginApp = NSWorkspace.shared.frontmostApplication

        postOverlayEnteredNotification(candidateCount: mru.count)
        overlay.show(candidates: overlayFiltered, selectedIndex: overlaySelectedIndex, searchText: overlaySearchText, showNumberBadges: showNumberBadges, onSelect: { [weak self] app in
            guard let self else { return }
            self.activateApp(app)
            self.hideOverlayAndCleanup(reactivateOrigin: false)
        })

        installOverlayEventMonitor()
        installOverlayActivationObserver()
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
            [.activateAllWindows],
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
                    self.axUnhideAndRaise(app)
                }
            }
            return
        }

        axUnhideAndRaise(app)
    }

    // MARK: - Overlay typing support

    private func installOverlayEventMonitor() {
        removeOverlayEventMonitor()

        overlayEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .keyDown:
                if self.handleOverlayKeyDown(event) { return nil }
                return event
            default:
                return event
            }
        }

        overlayGlobalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return }
            _ = self.handleOverlayKeyDown(event)
        }
    }

    private func removeOverlayEventMonitor() {
        if let monitor = overlayEventMonitor {
            NSEvent.removeMonitor(monitor)
            overlayEventMonitor = nil
        }
        if let global = overlayGlobalEventMonitor {
            NSEvent.removeMonitor(global)
            overlayGlobalEventMonitor = nil
        }
    }

    private func installOverlayActivationObserver() {
        removeOverlayActivationObserver()

        overlayActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            guard self.overlayIsVisible() else { return }
            guard let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }

            let myPID = ProcessInfo.processInfo.processIdentifier
            if activated.processIdentifier != myPID {
                self.hideOverlayAndCleanup(reactivateOrigin: false)
            }
        }
    }

    private func removeOverlayActivationObserver() {
        if let obs = overlayActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            overlayActivationObserver = nil
        }
    }

    private func eventToShortcut(_ event: NSEvent) -> Shortcut {
        let keyCode = UInt32(event.keyCode)
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift, .capsLock, .function])
        return Shortcut(keyCode: keyCode, modifiers: mods)
    }

    private func handleOverlayKeyDown(_ event: NSEvent) -> Bool {
        let asShortcut = eventToShortcut(event)

        if asShortcut == overlaySelectShortcut {
            if let idx = overlaySelectedIndex, overlayFiltered.indices.contains(idx) {
                let app = overlayFiltered[idx]
                activateApp(app)
                hideOverlayAndCleanup(reactivateOrigin: false)
            }
            return true
        }

        if asShortcut == overlayQuitShortcut {
            quitSelectedAppAndStay()
            return true
        }

        if let charsIgnoringMods = event.charactersIgnoringModifiers, charsIgnoringMods.count == 1 {
            let c = charsIgnoringMods.unicodeScalars.first!
            switch c.value {
            case 0x1B:
                if overlaySearchText.isEmpty {
                    hideOverlayAndCleanup(reactivateOrigin: true)
                } else {
                    overlaySearchText = ""
                    recomputeOverlayFilterAndUpdate()
                }
                return true
            case 0x7F:
                if !overlaySearchText.isEmpty {
                    overlaySearchText.removeLast()
                    recomputeOverlayFilterAndUpdate()
                }
                return true
            default:
                break
            }
        }

        if let special = event.specialKey {
            switch special {
            case .leftArrow:  moveSelection(delta: -1); return true
            case .rightArrow: moveSelection(delta:  1); return true
            case .tab:
                let delta = event.modifierFlags.contains(.shift) ? -1 : 1
                moveSelection(delta: delta)
                return true
            default: break
            }
        }

        if let chars = event.characters, !chars.isEmpty {
            let scalars = chars.unicodeScalars
            if scalars.count == 1, let digit = scalars.first, ("0"..."9").contains(Character(digit)) {
                if selectByDigit(Character(digit)) { return true }
            }

            let printableScalars = scalars.filter { scalar in
                switch scalar.properties.generalCategory {
                case .control, .format, .surrogate, .privateUse, .unassigned: return false
                default: return true
                }
            }
            if !printableScalars.isEmpty {
                overlaySearchText.append(String(String.UnicodeScalarView(printableScalars)))
                recomputeOverlayFilterAndUpdate()
                return true
            }
        }

        return false
    }

    private func quitSelectedAppAndStay() {
        guard let idx = overlaySelectedIndex, overlayFiltered.indices.contains(idx) else { return }
        let app = overlayFiltered[idx]
        let name = app.localizedName ?? app.bundleIdentifier ?? "App"
        NSLog("Attempting to quit \(name)")

        _ = app.terminate()

        removeAppFromLists(app)

        overlay.showToast("Quit \(name)")

        overlay.update(candidates: overlayFiltered, selectedIndex: overlaySelectedIndex, searchText: overlaySearchText, showNumberBadges: showNumberBadges)
    }

    private func removeAppFromLists(_ app: NSRunningApplication) {
        mru.removeAll { $0.processIdentifier == app.processIdentifier }

        let wasIndex = overlaySelectedIndex
        overlayFiltered.removeAll { $0.processIdentifier == app.processIdentifier }

        if overlayFiltered.isEmpty {
            overlaySelectedIndex = nil
        } else if let wasIndex {
            let newIndex = min(wasIndex, overlayFiltered.count - 1)
            overlaySelectedIndex = max(0, newIndex)
        } else {
            overlaySelectedIndex = 0
        }
    }

    private func selectByDigit(_ ch: Character) -> Bool {
        guard !overlayFiltered.isEmpty else { return false }
        let index: Int
        switch ch {
        case "1"..."9": index = Int(String(ch))! - 1
        case "0":      index = 9
        default:       return false
        }
        guard overlayFiltered.indices.contains(index) else { return false }
        let app = overlayFiltered[index]
        activateApp(app)
        hideOverlayAndCleanup(reactivateOrigin: false)
        return true
    }

    private func moveSelection(delta: Int) {
        guard !overlayFiltered.isEmpty else { return }
        let count = overlayFiltered.count
        let current = overlaySelectedIndex ?? 0
        let next = (current + (delta % count) + count) % count
        overlaySelectedIndex = next
        overlay.update(candidates: overlayFiltered, selectedIndex: overlaySelectedIndex, searchText: overlaySearchText, showNumberBadges: showNumberBadges)
    }

    private func recomputeOverlayFilterAndUpdate() {
        if overlaySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            overlayFiltered = mru
        } else {
            let needle = overlaySearchText.lowercased()
            overlayFiltered = mru.filter { app in
                let name = (app.localizedName ?? app.bundleIdentifier ?? "").lowercased()
                return matchesWordPrefix(name: name, query: needle)
            }
        }
        overlaySelectedIndex = overlayFiltered.isEmpty ? nil : min(overlaySelectedIndex ?? 0, overlayFiltered.count - 1)
        overlay.update(candidates: overlayFiltered, selectedIndex: overlaySelectedIndex, searchText: overlaySearchText, showNumberBadges: showNumberBadges)

        if autoSelectSingleResult && overlayFiltered.count == 1, let only = overlayFiltered.first {
            activateApp(only)
            hideOverlayAndCleanup(reactivateOrigin: false)
        }
    }

    private func matchesWordPrefix(name: String, query: String) -> Bool {
        let nameWords = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let queryTokens = query.split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
        guard !queryTokens.isEmpty else { return true }
        for token in queryTokens {
            var matched = false
            for word in nameWords where word.hasPrefix(token) { matched = true; break }
            if !matched { return false }
        }
        return true
    }

    // MARK: - Window cycling (fixed stack per activation, reset on count change)

    private func resetWindowCycleStacks(exceptPID pid: pid_t) {
        windowCycleStackByPID = windowCycleStackByPID.filter { $0.key == pid }
        windowCycleIndexByPID = windowCycleIndexByPID.filter { $0.key == pid }
        windowCycleLastStableIDByPID.removeAll()
        windowCycleLastIndexByPID.removeAll()
    }

    private func captureWindowStack(for app: NSRunningApplication) -> [AppWindow] {
        let windows = WindowEnumerator.windows(for: app)
        return windows
    }

    private func isAXElementValid(_ element: AXUIElement) -> Bool {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        return err == .success
    }

    private func togglePreviousWindowInFrontmostApp() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            NSLog("[Cycle] No frontmost application.")
            return
        }
        let pid = frontApp.processIdentifier
        let liveWindows = captureWindowStack(for: frontApp)
        let cachedCount = windowCycleStackByPID[pid]?.count
        if windowCycleStackByPID[pid] == nil || cachedCount != liveWindows.count {
            if liveWindows.isEmpty {
                NSLog("[Cycle] No windows to cycle.")
                windowCycleStackByPID[pid] = nil
                windowCycleIndexByPID[pid] = nil
                return
            }
            windowCycleStackByPID[pid] = liveWindows
            if liveWindows.count >= 2 {
                windowCycleIndexByPID[pid] = 0
            } else {
                windowCycleIndexByPID[pid] = -1
            }
            NSLog("[Cycle] (Re)captured \(liveWindows.count) windows for PID \(pid) due to count change or first use.")
        }

        guard var stack = windowCycleStackByPID[pid], !stack.isEmpty else {
            NSLog("[Cycle] Stack empty for PID \(pid).")
            return
        }

        var nextIndex: Int = {
            let current = windowCycleIndexByPID[pid] ?? -1
            return (current + 1) % stack.count
        }()

        var safety = 0
        while safety < 2 * max(stack.count, 1) {
            let candidate = stack[nextIndex]
            if isAXElementValid(candidate.axElement) {
                break
            } else {
                stack.remove(at: nextIndex)
                windowCycleStackByPID[pid] = stack
                if stack.isEmpty {
                    windowCycleIndexByPID[pid] = -1
                    NSLog("[Cycle] All windows gone for PID \(pid).")
                    return
                }
                nextIndex = nextIndex % stack.count
            }
            safety += 1
        }

        let target = stack[nextIndex]
        windowCycleIndexByPID[pid] = nextIndex

        NSLog("[Cycle] Activating windowNumber=\(target.windowNumber) index=\(nextIndex) of \(stack.count)")
        WindowEnumerator.activate(window: target)
        if let app = NSRunningApplication(processIdentifier: pid) {
            _ = app.activate(options: [.activateAllWindows])
        }
    }

    // MARK: - Notifications

    private func requestNotificationAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { NSLog("Notification authorization error: \(error.localizedDescription)") }
            else { NSLog("Notification authorization granted: \(granted)") }
        }
    }

    private func postDebugNotification() {
        postNotification(title: "Switcheroo", body: "Quick switched to previous app.")
    }

    private func postOverlayEnteredNotification(candidateCount: Int) {
        postNotification(title: "Switcheroo", body: "Overlay shown with \(candidateCount) apps.")
    }

    private func postWindowCycleNotification() {
        postNotification(title: "Switcheroo", body: "Window cycle hotkey pressed.", identifierPrefix: "cycle-")
    }

    private func postNotification(title: String, body: String, identifierPrefix: String = "") {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: identifierPrefix + UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("Notification failed: \(error.localizedDescription)") }
        }
    }

    private func axUnhideAndRaise(_ app: NSRunningApplication) {
        _ = app.unhide()
        _ = app.activate(options: [])
    }
}
