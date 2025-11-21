import SwiftUI

/// Behavior configuration section: toggles and long-press delay.
struct BehaviorSection: View {
    @EnvironmentObject private var switcher: Switcher
    @State private var separateMode: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                NumberBadgesSettingsView_Checkbox()
                AutoSelectSingleResultSettingsView_Checkbox()
                Toggle("Separate key switch", isOn: $separateMode)
                    .toggleStyle(.checkbox)
                    .onChange(of: separateMode) { _, new in
                        switcher.setSeparateKeySwitchEnabled(new)
                    }
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                if !switcher.separateKeySwitchEnabled {
                    GridRow {
                        Text("Long‑Press Delay:")
                            .gridLabel()
                        LongPressDelaySettingsView()
                    }
                }
            }
        }
        .onAppear {
            separateMode = switcher.separateKeySwitchEnabled
        }
    }
}
