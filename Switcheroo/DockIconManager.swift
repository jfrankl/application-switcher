import AppKit

/// Controls whether the app shows a Dock icon by switching activation policy.
/// Persists the preference in UserDefaults.
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
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
