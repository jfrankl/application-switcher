import SwiftUI

/// Displays and binds all shortcut pickers to Switcher.
struct ShortcutsSection: View {
    @EnvironmentObject private var switcher: Switcher
    @State private var appSwitch = Shortcut.load()
    @State private var windowCycle: Shortcut = .default

    // Overlay actions
    @State private var overlaySelect: Shortcut = Shortcut(keyCode: 36, modifiers: [])
    @State private var overlayQuit: Shortcut = Shortcut(keyCode: 12, modifiers: [.command])

    // Separate mode state
    @State private var separateToggle: Shortcut = Shortcut(keyCode: 111, modifiers: []) // F12
    @State private var separateOverlay: Shortcut = Shortcut(keyCode: 103, modifiers: []) // F11

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                if switcher.separateKeySwitchEnabled {
                    GridRow {
                        Text("Open app panel / cycle")
                            .gridLabel()
                        ShortcutPicker(shortcut: $separateOverlay)
                            .frame(width: 220)
                            .onChange(of: separateOverlay) { _, new in
                                switcher.applySeparateOverlayShortcut(new)
                            }
                    }

                    GridRow {
                        Text("Toggle previous app")
                            .gridLabel()
                        ShortcutPicker(shortcut: $separateToggle)
                            .frame(width: 220)
                            .onChange(of: separateToggle) { _, new in
                                switcher.applySeparateToggleShortcut(new)
                            }
                    }
                } else {
                    GridRow {
                        Text("Application Switcher Shortcut")
                            .gridLabel()
                        ShortcutPicker(shortcut: $appSwitch)
                            .frame(width: 220)
                            .onChange(of: appSwitch) { _, new in
                                new.save()
                                switcher.applyAppSwitchShortcut(new)
                            }
                    }
                }

                GridRow {
                    Text("Window Switcher Shortcut")
                        .gridLabel()
                    ShortcutPicker(shortcut: $windowCycle)
                        .frame(width: 220)
                        .onChange(of: windowCycle) { _, new in
                            switcher.applyWindowCycleShortcut(new)
                        }
                }

                GridRow {
                    Text("Select highlighted app")
                        .gridLabel()
                    ShortcutPicker(shortcut: $overlaySelect)
                        .frame(width: 220)
                        .onChange(of: overlaySelect) { _, new in
                            switcher.applyOverlaySelectShortcut(new)
                        }
                }
                GridRow {
                    Text("Quit selected app")
                        .gridLabel()
                    ShortcutPicker(shortcut: $overlayQuit)
                        .frame(width: 220)
                        .onChange(of: overlayQuit) { _, new in
                            switcher.applyOverlayQuitShortcut(new)
                        }
                }
            }
        }
        .onAppear {
            appSwitch = Shortcut.load()
            windowCycle = switcher.windowCycleShortcut
            overlaySelect = switcher.overlaySelectShortcut
            overlayQuit = switcher.overlayQuitShortcut

            separateToggle = switcher.separateToggleShortcut
            separateOverlay = switcher.separateOverlayShortcut
        }
    }
}
