import SwiftUI

/// Root preferences window content.
/// Composes sections and applies consistent sizing.
struct PreferencesRootView: View {
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SectionHeader("General")

                    // Overview contains version, support, tip, and feedback button
                    OverviewSection()

                    SectionHeader("Behavior")
                    BehaviorSection()

                    Divider().opacity(0.25).padding(.vertical, 6)

                    SectionHeader("Shortcuts")
                    ShortcutsSection()
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 620, height: 400)
        }
        .frame(width: 620, height: 400)
    }

    // Kept here for reuse by OverviewSection
    func openAppStoreFeedback() {
        let fallback = URL(string: "https://apps.apple.com/app/id1234567890?action=write-review")!
        let deepLink = URL(string: "macappstore://apps.apple.com/app/id1234567890?action=write-review")
        let urlToOpen = deepLink ?? fallback
        let opened = NSWorkspace.shared.open(urlToOpen)
        if !opened {
            _ = NSWorkspace.shared.open(fallback)
        }
    }
}

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, -6)
    }
}

extension Text {
    func gridLabel() -> some View {
        self
            .font(.system(size: 13))
            .frame(width: 210, alignment: .trailing)
            .foregroundStyle(.secondary)
    }
}
