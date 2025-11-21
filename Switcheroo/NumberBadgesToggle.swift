import SwiftUI

/// Toggle to show/hide number badges on overlay items.
struct NumberBadgesSettingsView_Checkbox: View {
    @EnvironmentObject private var switcher: Switcher
    var body: some View {
        Toggle(isOn: Binding(
            get: { switcher.showNumberBadges },
            set: { switcher.setShowNumberBadges($0) }
        )) {
            Text("Show number badges in overlay")
        }
        .toggleStyle(.checkbox)
    }
}
