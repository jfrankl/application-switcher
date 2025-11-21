import SwiftUI
import AppKit

/// Resolves and renders high-quality application icons for NSRunningApplication.
/// Encapsulates AppKit specifics and simple in-memory caching to keep SwiftUI views light.
private enum AppIconResolver {

    /// Shared in-memory cache keyed by PID then bundleID and target size.
    /// PID is used first to disambiguate multiple instances; bundleID serves as a fallback.
    private static var cache = NSCache<NSString, NSImage>()
    private static let cachePrefix = "appicon:"

    /// Fetch a best-rendered icon at a specific size for a running application.
    /// - Parameters:
    ///   - app: The running application.
    ///   - size: The desired square size in points/pixels (backed by NSImage points).
    /// - Returns: An NSImage rendered at the requested size, or nil if resolution fails.
    static func icon(for app: NSRunningApplication, size: CGFloat) -> NSImage? {
        let key = cacheKey(for: app, size: size)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        guard let source = iconSource(for: app) else { return nil }
        guard let rendered = render(image: source, to: NSSize(width: size, height: size)) else { return nil }

        cache.setObject(rendered, forKey: key as NSString)
        return rendered
    }

    /// Best-effort to obtain an icon image for the app, preferring the running app’s icon.
    private static func iconSource(for app: NSRunningApplication) -> NSImage? {
        if let img = app.icon { return img }

        if let url = app.bundleURL {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        if let bundleID = app.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        return nil
    }

    /// Render an NSImage at a target size using its best representation.
    /// This avoids mutating image.size and produces sharper results for template/bitmap icons.
    private static func render(image: NSImage, to targetSize: NSSize) -> NSImage? {
        let rect = NSRect(origin: .zero, size: targetSize)

        // Ask NSImage for its best representation at the target rect.
        if let rep = image.bestRepresentation(for: rect, context: nil, hints: nil) {
            let output = NSImage(size: targetSize)
            output.lockFocus()
            defer { output.unlockFocus() }
            rep.draw(in: rect)
            output.isTemplate = image.isTemplate
            return output
        }

        // Fallback: draw the image itself (handles vector/template cases reasonably).
        let output = NSImage(size: targetSize)
        output.lockFocus()
        defer { output.unlockFocus() }
        image.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0, respectFlipped: true, hints: [
            .interpolation: NSImageInterpolation.high
        ])
        output.isTemplate = image.isTemplate
        return output
    }

    /// A cache key that tries PID first (handles multiple instances), then bundleID, then localizedName.
    private static func cacheKey(for app: NSRunningApplication, size: CGFloat) -> String {
        let pidPart = "pid:\(app.processIdentifier)"
        if let bundleID = app.bundleIdentifier {
            return "\(cachePrefix)\(pidPart)|bid:\(bundleID)|s:\(Int(size))"
        }
        let name = app.localizedName ?? "Unnamed"
        return "\(cachePrefix)\(pidPart)|name:\(name)|s:\(Int(size))"
    }
}

struct AppIconView: View {
    let app: NSRunningApplication
    let size: CGFloat
    private let cornerRadius: CGFloat = 12

    var body: some View {
        Group {
            if let icon = AppIconResolver.icon(for: app, size: size) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(Color.black.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// A simple placeholder for when an icon cannot be resolved.
    private var placeholder: some View {
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
