import SwiftUI
import UIKit
import GrappleCore

/// Live sliders for every feel parameter (issue #9). Changes apply immediately.
struct TuningPanel: View {
    @Binding var tuning: Tuning
    /// Plays a test sound and returns a description of the audio setup.
    var onSoundCheck: () -> String = { "" }
    @State private var copied = false
    @State private var soundReport: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                slider("Game speed (×)", $tuning.gameSpeed, 0.4...1.2)
                slider("Relaxed pace ×", $tuning.paceRelaxedFactor, 0.5...1)
                slider("Fast pace ×", $tuning.paceFastFactor, 1...1.6)
                Toggle("Flips allowed", isOn: $tuning.allowsSpins).font(.caption)
                slider("Gravity", $tuning.gravity, 200...5000)
                slider("Swing gravity ×", $tuning.swingGravityMultiplier, 0.5...4)
                slider("Air drag", $tuning.airDrag, 0...2)
                slider("Max speed", $tuning.maxSpeed, 500...6000)
                slider("Min rope range", $tuning.ropeRange, 200...1500)
                slider("Range past screen edge (×)", $tuning.ropeRangeScreenFactor, 0.5...2)
                slider("Rope tip speed", $tuning.ropeTipSpeed, 500...8000)
                slider("Min rope length", $tuning.minRopeLength, 10...200)
                slider("Attach tug speed", $tuning.attachTugSpeed, 0...2000)
                slider("Assist radius", $tuning.aimAssistRadius, 0...400)
                slider("Assist angle (°)", $tuning.aimAssistAngleDegrees, 0...45)
                slider("Assist angle when blocked (°)", $tuning.aimAssistBlockedAngleDegrees, 0...90)
                slider("Retract delay (s)", $tuning.retractDelay, 0...1)
                slider("Retract speed", $tuning.retractSpeed, 0...2000)
                slider("Retract min length", $tuning.retractMinLength, 45...400)
                slider("Retract momentum carry", $tuning.retractMomentumCarry, 0...1)
                slider("Boost min speed", $tuning.boostMinSpeed, 0...2000)
                slider("Boost impulse", $tuning.boostImpulse, 0...1500)
                slider("Release lift", $tuning.releaseLift, 0...1000)
                slider("Boost min angle (°)", $tuning.boostMinAngleDegrees, 0...90)
                slider("Boost max angle (°)", $tuning.boostMaxAngleDegrees, 0...90)
                slider("Sand friction", $tuning.sandFriction, 0...80)
                slider("Sand tug factor", $tuning.sandTugFactor, 0...1)
                slider("Wind strength ×", $tuning.windStrength, 0...3)
                slider("Gem pickup radius", $tuning.gemPickupRadius, 10...120)
                slider("Flip chance", $tuning.flipChance, 0...1)
                slider("Flip min speed", $tuning.flipMinSpeed, 0...2000)
                slider("Speed per spin/sec", $tuning.spinSpeedPerRotation, 200...3000)
                slider("Min spins/sec", $tuning.spinMinRotations, 0.5...3)
                slider("Max spins/sec", $tuning.spinMaxRotations, 1...6)
                slider("Limb stiffness", $tuning.limbStiffness, 0...40)
                slider("Limb damping", $tuning.limbDamping, 0...10)
                slider("Hit-stop (s)", $tuning.hitStopSeconds, 0...0.4)
                slider("Speed zoom", $tuning.speedZoom, 0...1)
                slider("Speed for full zoom", $tuning.speedZoomFullSpeed, 500...5000)
                slider("Screen shake", $tuning.screenShake, 0...50)
                slider("Crash impact speed", $tuning.crashImpactSpeed, 200...4000)
                slider("Surface friction", $tuning.surfaceFriction, 0...20)

                Button("Sound check") { soundReport = onSoundCheck() }
                    .buttonStyle(.bordered)
                if let soundReport {
                    Text(soundReport)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Reset") { tuning = .default }
                    Spacer()
                    Button(copied ? "Copied" : "Copy JSON") { copyJSON() }
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
        }
        .frame(width: 300)
        .frame(maxHeight: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
            }
            .font(.caption)
            Slider(value: value, in: range)
        }
    }

    /// Copies the current values so good settings can be pasted back as the new defaults in `Tuning.swift`.
    private func copyJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(tuning), let json = String(data: data, encoding: .utf8) else { return }
        UIPasteboard.general.string = json
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
