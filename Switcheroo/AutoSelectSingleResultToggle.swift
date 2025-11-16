import SwiftUI

struct AutoSelectSingleResultSettingsView_Checkbox: View {
    @EnvironmentObject private var switcher: Switcher

    var body: some View {
        Toggle(isOn: Binding(
            get: { switcher.autoSelectSingleResult },
            set: { switcher.setAutoSelectSingleResult($0) }
        )) {
            Text("Auto-select when only one match remains")
        }
        .toggleStyle(.checkbox)
    }
}
