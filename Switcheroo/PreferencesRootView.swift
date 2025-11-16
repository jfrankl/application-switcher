import SwiftUI

struct PreferencesRootView: View {
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SectionHeader("General")
                    OverviewSection()

                    SectionHeader("Shortcuts")
                    ShortcutsSection()

                    SectionHeader("Behavior")
                    BehaviorSection()
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 620, height: 400)
        }
        .frame(width: 620, height: 400)
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
