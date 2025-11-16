import SwiftUI

struct BehaviorSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Long‑Press Delay:")
                        .gridLabel()
                    LongPressDelaySettingsView()
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                NumberBadgesSettingsView_Checkbox()
                AutoSelectSingleResultSettingsView_Checkbox()
            }
        }
    }
}
