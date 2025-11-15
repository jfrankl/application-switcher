import SwiftUI
import AppKit

struct SwitchOverlayView: View {
    let candidates: [NSRunningApplication]
    let selectedIndex: Int?
    let searchText: String
    let onSelect: (NSRunningApplication) -> Void

    private let itemSize: CGFloat = 72
    private let iconSize: CGFloat = 56
    private let cornerRadius: CGFloat = 14

    var body: some View {
        ZStack {
            debugBackdrop
            frostedBackground
            VStack(spacing: 12) {
                if !searchText.isEmpty {
                    searchBadge
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                itemsScrollView
            }
            .padding(.top, 8)
            .padding(.bottom, 6)
            .padding(.horizontal, 8)
        }
        .padding(20)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.12), value: searchText)
    }

    // MARK: - Components

    private var debugBackdrop: some View {
        Color.black.opacity(0.25)
    }

    private var frostedBackground: some View {
        VisualEffectView(material: .hudWindow, blendingMode: .withinWindow, emphasized: false)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
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
                    itemView(app: app, isSelected: idx == selectedIndex)
                        .onTapGesture {
                            onSelect(app)
                        }
                }
            }
            .padding(16)
        }
        .frame(minHeight: 120)
        .padding(6)
    }

    @ViewBuilder
    private func itemView(app: NSRunningApplication, isSelected: Bool) -> some View {
        VStack(spacing: 8) {
            iconView(app: app, isSelected: isSelected)
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
}

