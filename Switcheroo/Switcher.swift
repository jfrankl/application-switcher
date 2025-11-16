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
    }

    @Published var backgroundColor: Color = Color(NSColor.windowBackgroundColor)

    @Published private(set) var longPressThreshold: TimeInterval
    static let defaultLongPressDelay: TimeInterval = 1.0
    private static let longPressDefaultsKey = "LongPressDelay"

    @Published private(set) var showNumberBadges: Bool
    private static let numberBadgesDefaultsKey = "ShowNumberBadges"

    @Published private(set) var autoSelectSingleResult: Bool
    private static let autoSelectDefaultsKey = "AutoSelectSingleResult"

    private var pressStart: Date?
    private var longPressTimer: DispatchSourceTimer?
    private var actionConsumedForThisPress = false

    private var activationObserver: Any?
    private var mru: [NSRunningApplication] = []

    private let overlay = OverlayWindowController()

    private var shortcut: Shortcut = .default

    @Published private(set) var windowCycleShortcut: Shortcut

    private var overlaySearchText: String = ""
    private var overlayFiltered: [NSRunningApplication] = []
    private var overlaySelectedIndex: Int? = nil
    private var overlayEventMonitor: Any?
    private var overlayGlobalEventMonitor: Any?

    private var overlayOriginApp: NSRunningApplication?

    private var windowCycleLastStableIDByPID: [pid_t: Int] = [:]
    private var windowCycleLastIndexByPID: [pid_t: Int] = [:]

    private enum HotKeyID: UInt32 {
        case appSwitch = 1
        case windowCycle = 2
    }

    func start() {
        requestNotificationAuthorization()

        shortcut = Shortcut.load()
        applyAppSwitchShortcut(shortcut)
        applyWindowCycleShortcut(windowCycleShortcut)

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

    func applyAppSwitchShortcut(_ shortcut: Shortcut) {
        self.shortcut = shortcut
        HotKeyManager.shared.register(id: HotKeyID.appSwitch.rawValue, shortcut: shortcut) { [weak self] event in
            switch event {
            case .pressed: self?.onHotkeyPressed()
            case .released: self?.onHotkeyReleased()
            }
        }
    }

    func applyWindowCycleShortcut(_ shortcut: Shortcut) {
        windowCycleShortcut = shortcut
        Self.saveWindowCycleShortcut(shortcut)
        HotKeyManager.shared.register(id: HotKeyID.windowCycle.rawValue, shortcut: shortcut) { [weak self] event in
            guard let self else { return }
            switch event {
            case .pressed:
                self.postWindowCycleNotification()
                self.togglePreviousWindowInFrontmostApp()
            case .released:
                break
            }
        }
    }

    func applyLongPressDelay(_ value: TimeInterval) {
        let clamped = max(0.05, min(5.0, value))
        guard clamped != longPressThreshold else { return }
        longPressThreshold = clamped
        UserDefaults.standard.set(clamped, forKey: Self.longPressDefaultsKey)

        if pressStart != nil {
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

    private func overlayIsVisible() -> Bool {
        overlayEventMonitor != nil || overlayGlobalEventMonitor != nil
    }

    private func onHotkeyPressed() {
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

    private func hideOverlayAndCleanup(reactivateOrigin: Bool) {
        overlay.hide(animated: true)
        removeOverlayEventMonitor()
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

    private func handleOverlayKeyDown(_ event: NSEvent) -> Bool {
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
            case 0x0D, 0x03:
                if let idx = overlaySelectedIndex, overlayFiltered.indices.contains(idx) {
                    let app = overlayFiltered[idx]
                    activateApp(app)
                    hideOverlayAndCleanup(reactivateOrigin: false)
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

    // MARK: - Window cycling

    private func focusedWindowNumber(for app: NSRunningApplication) -> Int? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindowValue: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowValue)
        guard err == .success, let focusedWindow = focusedWindowValue else { return nil }

        var numValue: CFTypeRef?
        let numErr = AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, "AXWindowNumber" as CFString, &numValue)
        if numErr == .success, let n = numValue as? Int { return n }
        return nil
    }

    private func togglePreviousWindowInFrontmostApp() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            NSLog("[Cycle] No frontmost application.")
            return
        }
        let windows = WindowEnumerator.windows(for: frontApp)
        NSLog("[Cycle] Front app: \(frontApp.localizedName ?? frontApp.bundleIdentifier ?? "App") windows=\(windows.map { "\($0.windowNumber):\($0.title ?? "")" })")
        guard !windows.isEmpty else {
            NSLog("[Cycle] No windows to cycle.")
            return
        }

        let pid = frontApp.processIdentifier

        if let lastIndex = windowCycleLastIndexByPID[pid], windows.indices.contains(lastIndex) {
            let nextIndex = (lastIndex + 1) % windows.count
            let target = windows[nextIndex]
            NSLog("[Cycle] (lastIndex) -> Activating windowNumber=\(target.windowNumber) title=\(target.title ?? "")")
            WindowEnumerator.activate(window: target)
            if let app = NSRunningApplication(processIdentifier: pid) {
                _ = app.activate(options: [.activateAllWindows])
            }
            windowCycleLastStableIDByPID[pid] = target.stableID
            windowCycleLastIndexByPID[pid] = nextIndex
            return
        }

        let focusedNumber = focusedWindowNumber(for: frontApp)
        let anchorIndex: Int = {
            if let lastStable = windowCycleLastStableIDByPID[pid],
               let idx = windows.firstIndex(where: { $0.stableID == lastStable }) {
                return idx
            }
            if let fnum = focusedNumber,
               let idx = windows.firstIndex(where: { $0.windowNumber == fnum }) {
                return idx
            }
            return 0
        }()

        let nextIndex = (anchorIndex + 1) % windows.count
        let target = windows[nextIndex]
        NSLog("[Cycle] (anchor) -> Activating windowNumber=\(target.windowNumber) title=\(target.title ?? "")")
        WindowEnumerator.activate(window: target)
        if let app = NSRunningApplication(processIdentifier: pid) {
            _ = app.activate(options: [.activateAllWindows])
        }
        windowCycleLastStableIDByPID[pid] = target.stableID
        windowCycleLastIndexByPID[pid] = nextIndex
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
