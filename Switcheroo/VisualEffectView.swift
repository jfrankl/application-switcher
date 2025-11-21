import SwiftUI
import AppKit

/// SwiftUI wrapper for NSVisualEffectView to get macOS materials in SwiftUI layouts.
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let emphasized: Bool

    init(material: NSVisualEffectView.Material,
         blendingMode: NSVisualEffectView.BlendingMode,
         emphasized: Bool = false) {
        self.material = material
        self.blendingMode = blendingMode
        self.emphasized = emphasized
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    /// Centralized configuration to keep make/update in sync.
    private func configure(_ view: NSVisualEffectView) {
        view.state = .active
        view.material = material
        view.blendingMode = blendingMode
        if #available(macOS 11.0, *) {
            view.isEmphasized = emphasized
        }
    }
}
