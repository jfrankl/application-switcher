import SwiftUI

/// Slider + stepper to control long-press delay, with live persistence via Switcher.
struct LongPressDelaySettingsView: View {
    @EnvironmentObject private var switcher: Switcher
    @State private var tempDelay: Double = 0

    private let range: ClosedRange<Double> = 0...3.0
    private let step: Double = 0.05

    var body: some View {
        HStack(spacing: 12) {
            Slider(value: $tempDelay, in: range, step: step, onEditingChanged: { editing in
                if !editing { apply() }
            })
            .frame(width: 240)

            Stepper(value: $tempDelay, in: range, step: step) { EmptyView() }
                .onChange(of: tempDelay) { _, _ in apply() }

            Text(String(format: "%.2fs", tempDelay))
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .onAppear { tempDelay = switcher.longPressThreshold }
    }

    private func apply() {
        switcher.applyLongPressDelay(tempDelay)
    }
}
