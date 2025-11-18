import SwiftUI

struct BehaviorSection: View {
    @EnvironmentObject private var switcher: Switcher

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                if !switcher.separateKeySwitchEnabled {
                    GridRow {
                        Text("Long‑Press Delay:")
                            .gridLabel()
                        LongPressDelaySettingsView()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                NumberBadgesSettingsView_Checkbox()
                AutoSelectSingleResultSettingsView_Checkbox()
            }
        }
    }
}
