import SwiftUI
import AppKit

/// The overlay view that displays candidate applications, selection, and optional search text.
struct SwitchOverlayView: View {
    let candidates: [NSRunningApplication]
    let selectedIndex: Int?
    let searchText: String
    let showNumberBadges: Bool
    let onSelect: (NSRunningApplication) -> Void

    private let itemSize: CGFloat = 72
    private let iconSize: CGFloat = 56
    private let cornerRadius: CGFloat = 14

    var body: some View {
        ZStack {
            backdrop
            frostedBackground
            content
        }
        .padding(20)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.12), value: searchText)
        .animation(.easeInOut(duration: 0.12), value: showNumberBadges)
        .animation(.easeInOut(duration: 0.12), value: candidates.count)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Components

    private var backdrop: some View {
        Color.black.opacity(0.25)
            .accessibilityHidden(true)
    }

    private var frostedBackground: some View {
        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, emphasized: false)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(spacing: 12) {
            if !searchText.isEmpty {
                searchBadge
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if candidates.isEmpty {
                emptyStateView
                    .transition(.opacity)
            } else {
                itemsScrollView
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .padding(.horizontal, 8)
    }

    private var searchBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Text(searchText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .textCase(.none)
                .foregroundStyle(.primary)
                .accessibilityLabel("Search: \(searchText)")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
    }

    private var itemsScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Array(candidates.enumerated()), id: \.1.processIdentifier) { (idx, app) in
                    itemView(app: app, index: idx, isSelected: idx == selectedIndex)
                        .onTapGesture { onSelect(app) }
                }
            }
            .padding(16)
        }
        .frame(minHeight: 120)
        .padding(6)
    }

    // Empty state shown when no apps match the current filter
    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "binoculars")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No applications found")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            Text(emptyStateMessage)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 12)
        .frame(minHeight: 120)
        .accessibilityLabel(emptyStateMessage)
    }

    private var emptyStateMessage: String {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "There are no applications to display right now."
        } else {
            return "No applications match “\(searchText)”. Try a different name or clear the search."
        }
    }

    @ViewBuilder
    private func itemView(app: NSRunningApplication, index: Int, isSelected: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                iconView(app: app, isSelected: isSelected)
                if showNumberBadges && index < 10 {
                    numberBadge(number: index == 9 ? "0" : "\(index + 1)")
                        .offset(x: -6, y: -6)
                        .accessibilityHidden(true)
                }
            }
            nameView(app: app, isSelected: isSelected)
        }
        .frame(width: itemSize)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: app, index: index, isSelected: isSelected))
    }

    @ViewBuilder
    private func iconView(app: NSRunningApplication, isSelected: Bool) -> some View {
        AppIconView(app: app, size: iconSize)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 3)
                        .shadow(color: Color.accentColor.opacity(0.6), radius: 8, x: 0, y: 0)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func nameView(app: NSRunningApplication, isSelected: Bool) -> some View {
        let name = app.localizedName ?? app.bundleIdentifier ?? "App"
        Text(name)
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .lineLimit(1)
            .frame(width: itemSize)
            .truncationMode(.tail)
    }

    private func numberBadge(number: String) -> some View {
        Text(number)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.25), lineWidth: 1)
                    )
            )
    }

    private func accessibilityLabel(for app: NSRunningApplication, index: Int, isSelected: Bool) -> String {
        let name = app.localizedName ?? app.bundleIdentifier ?? "App"
        let prefix = isSelected ? "Selected" : "Item"
        let badge = showNumberBadges && index < 10 ? ", shortcut \(index == 9 ? "0" : "\(index + 1)")" : ""
        return "\(prefix): \(name)\(badge)"
    }
}
