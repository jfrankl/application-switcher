import SwiftUI
import AppKit

/// App entry point. Creates and injects the Switcher and status bar item.
@main
struct SwitcherooApp: App {
    @StateObject private var switcher = Switcher()

    private let statusBarController = StatusBarController()

    var body: some Scene {
        WindowGroup {
            PreferencesRootView()
                .padding(.vertical, 16)
                .environmentObject(switcher)
                .background(switcher.backgroundColor.ignoresSafeArea())
                .onAppear {
                    DispatchQueue.main.async {
                        DockIconManager.shared.applyCurrentPreference()
                        statusBarController.installStatusItem()
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    switcher.start()
                }
        }
        .defaultSize(width: 620, height: 400)
        .windowResizability(.contentSize)
    }
}
