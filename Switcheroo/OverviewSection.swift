import SwiftUI

/// Displays version/support info, a tip, and a feedback button.
/// Uses an environment-provided closure to open the App Store page.
struct OverviewSection: View {
    @Environment(\.openFeedback) private var openFeedback

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
                    Link("Open GitHub", destination: URL(string: "https://github.com/jfrankl/switchie/")!)
                }
            }

            Text("Tip: If media keys adjust volume, enable “Use F1, F2, etc. keys as standard function keys” or hold Fn while pressing function keys. Accessibility permission may be requested for full control features.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button {
                    openFeedback()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "star.bubble.fill")
                            .imageScale(.medium)
                        Text("Leave Feedback on the App Store")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(.white.opacity(0.12), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .help("Open the App Store page to leave a rating or feedback.")
                Spacer()
            }

            Divider().opacity(0.25).padding(.vertical, 6)
        }
    }

    private func appVersionString() -> String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(v) (\(b))"
    }
}

// Environment key to let OverviewSection call PreferencesRootView's opener
private struct OpenFeedbackKey: EnvironmentKey {
    static let defaultValue: () -> Void = { }
}

extension EnvironmentValues {
    var openFeedback: () -> Void {
        get { self[OpenFeedbackKey.self] }
        set { self[OpenFeedbackKey.self] = newValue }
    }
}

// Inject the opener from PreferencesRootView
extension PreferencesRootView {
    func environmentValues(_ values: inout EnvironmentValues) {
        values.openFeedback = { self.openAppStoreFeedback() }
    }
}
