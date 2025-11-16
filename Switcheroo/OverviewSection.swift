import SwiftUI

struct OverviewSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Version:")
                        .gridLabel()
                    Text(appVersionString()).monospacedDigit()
                }
                GridRow {
                    Text("Support:")
                        .gridLabel()
                    Link("Open GitHub", destination: URL(string: "https://github.com/")!)
                }
            }

            Text("Tip: If media keys adjust volume, enable “Use F1, F2, etc. keys as standard function keys” or hold Fn while pressing function keys. Accessibility permission may be requested for full control features.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.25).padding(.vertical, 6)
        }
    }

    private func appVersionString() -> String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(v) (\(b))"
    }
}
