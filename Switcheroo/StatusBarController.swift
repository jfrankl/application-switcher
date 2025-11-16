import AppKit

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
