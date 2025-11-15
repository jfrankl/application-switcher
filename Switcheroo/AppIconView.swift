import SwiftUI
import AppKit

struct AppIconView: View {
    let app: NSRunningApplication
    let size: CGFloat
    private let cornerRadius: CGFloat = 12

    var body: some View {
        Group {
            if let icon = resolvedIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
            } else {
                // Fallback placeholder if no icon is available
                ZStack {
                    Color(NSColor.windowBackgroundColor)
                    Image(systemName: "app.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .padding(size * 0.22)
                }
            }
        }
        .frame(width: size, height: size)
        .background(Color.black.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .drawingGroup(opaque: false, colorMode: .extendedLinear)
    }

    private var resolvedIcon: NSImage? {
        // Prefer the running app’s icon
        if let icon = app.icon {
            return resizedCopy(of: icon, to: NSSize(width: size, height: size))
        }

        // Fallback: try bundle URL
        if let url = app.bundleURL {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return resizedCopy(of: icon, to: NSSize(width: size, height: size))
        }

        // Fallback: try bundle identifier -> resolve to app URL
        if let bundleID = app.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return resizedCopy(of: icon, to: NSSize(width: size, height: size))
        }

        return nil
    }

    private func resizedCopy(of image: NSImage, to size: NSSize) -> NSImage? {
        guard let copy = image.copy() as? NSImage else { return nil }
        copy.size = size
        return copy
    }
}
