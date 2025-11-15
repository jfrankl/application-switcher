import SwiftUI
import AppKit

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
        view.state = .active
        view.material = material
        view.blendingMode = blendingMode
        if #available(macOS 11.0, *) {
            view.isEmphasized = emphasized
        }
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.state = .active
        nsView.material = material
        nsView.blendingMode = blendingMode
        if #available(macOS 11.0, *) {
            nsView.isEmphasized = emphasized
        }
    }
}
