import SwiftUI

struct ShortcutsSection: View {
    @EnvironmentObject private var switcher: Switcher
    @State private var appSwitch = Shortcut.load()
    @State private var windowCycle: Shortcut = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
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
                GridRow {
                    Text("Window Switcher Shortcut")
                        .gridLabel()
                    ShortcutPicker(shortcut: $windowCycle)
                        .frame(width: 220)
                        .onChange(of: windowCycle) { _, new in
                            switcher.applyWindowCycleShortcut(new)
                        }
                }
                Divider().opacity(0.25).padding(.vertical, 6)
            }
        }
        .onAppear {
            appSwitch = Shortcut.load()
            windowCycle = switcher.windowCycleShortcut
        }
    }
}
