import AppKit
import ApplicationServices

struct AppWindow {
    let windowNumber: Int
    let axElement: AXUIElement
    let title: String?

    // Stable identity derived from the AXUIElement pointer address.
    // This remains stable for the lifetime of the AX element.
    var stableID: Int {
        return Unmanaged.passUnretained(axElement).toOpaque().hashValue
    }
}

enum WindowEnumerator {
    // Enumerate standard, visible windows for the given app
    static func windows(for app: NSRunningApplication) -> [AppWindow] {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Check AX trust for better logging
        if !AXIsProcessTrusted() {
            NSLog("[AX] Not trusted. Enable Accessibility for this app.")
        }

        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        if err != .success {
            NSLog("[AX] Copy kAXWindowsAttribute failed: \(err.rawValue)")
            return []
        }
        guard let array = value as? [AXUIElement] else {
            NSLog("[AX] kAXWindowsAttribute not an array: \(String(describing: value))")
            return []
        }

        var result: [AppWindow] = []
        for (idx, axWin) in array.enumerated() {
            // Roles and subroles help distinguish real windows
            let role = getStringAttribute(axWin, kAXRoleAttribute as CFString) ?? "?"
            let subrole = getStringAttribute(axWin, kAXSubroleAttribute as CFString) ?? "?"
            let title = getStringAttribute(axWin, kAXTitleAttribute as CFString)

            // Filter to standard windows
            guard role == (kAXWindowRole as String) else {
                continue
            }

            // Skip sheets, drawers, popovers
            if !subrole.isEmpty, subrole != (kAXStandardWindowSubrole as String) {
                continue
            }

            // Minimized?
            if let minimized = getBoolAttribute(axWin, kAXMinimizedAttribute as CFString), minimized {
                continue
            }

            // Hidden?
            if let hidden = getBoolAttribute(axWin, kAXHiddenAttribute as CFString), hidden {
                continue
            }

            // Try window number via AXWindowNumber
            var number: Int?
            if let n = getIntAttribute(axWin, "AXWindowNumber" as CFString) {
                number = n
            } else {
                // Fallback synthetic number using index to keep ordering stable per enumeration
                number = 1_000_000 + idx
            }

            if let number {
                result.append(AppWindow(windowNumber: number, axElement: axWin, title: title))
            }
        }

        // Stable order by windowNumber (synthetic numbers preserve original order)
        result.sort { $0.windowNumber < $1.windowNumber }
        NSLog("[AX] Enumerated \(result.count) windows for \(app.localizedName ?? app.bundleIdentifier ?? "App")")
        return result
    }

    // Bring a window to front and focus it
    static func activate(window: AppWindow) {
        // Try AXRaise
        let raiseErr = AXUIElementPerformAction(window.axElement, kAXRaiseAction as CFString)
        if raiseErr != .success {
            NSLog("[AX] AXRaise failed: \(raiseErr.rawValue)")
        }

        // Try setting main and focused
        let trueValue = kCFBooleanTrue as CFBoolean
        let mainErr = AXUIElementSetAttributeValue(window.axElement, kAXMainAttribute as CFString, trueValue)
        let focusedErr = AXUIElementSetAttributeValue(window.axElement, kAXFocusedAttribute as CFString, trueValue)
        if mainErr != .success { NSLog("[AX] Set kAXMainAttribute failed: \(mainErr.rawValue)") }
        if focusedErr != .success { NSLog("[AX] Set kAXFocusedAttribute failed: \(focusedErr.rawValue)") }

        // Also ask AppKit to bring the owning app forward
        if let pid = window.axElement.processIdentifier,
           let app = NSRunningApplication(processIdentifier: pid) {
            _ = app.activate(options: [.activateAllWindows])
        }
    }

    // MARK: - Helpers

    private static func getStringAttribute(_ element: AXUIElement, _ attr: CFString) -> String? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, attr, &value)
        if err != .success { return nil }
        return value as? String
    }

    private static func getBoolAttribute(_ element: AXUIElement, _ attr: CFString) -> Bool? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, attr, &value)
        if err != .success { return nil }
        return value as? Bool
    }

    private static func getIntAttribute(_ element: AXUIElement, _ attr: CFString) -> Int? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, attr, &value)
        if err != .success { return nil }
        // Some apps return CFNumber or CFIndex; both bridge to Int
        return value as? Int
    }
}

private extension AXUIElement {
    var processIdentifier: pid_t? {
        var pid: pid_t = 0
        let status = AXUIElementGetPid(self, &pid)
        return status == .success ? pid : nil
    }
}
