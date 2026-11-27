import SwiftUI
import GrappleCore

/// The player's settings sheet (#36): pace, how opponents are drawn, and reduced motion.
struct SettingsView: View {
    @Binding var settings: PlayerSettings
    /// iOS's own Reduce Motion setting; when on, motion is reduced whatever the toggle says.
    var systemReduceMotion: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Pace", selection: $settings.pace) {
                        ForEach(PlayerSettings.Pace.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Pace")
                } footer: {
                    Text("Slows or speeds up the whole game. Your swings fly the same paths, and the bots play at your pace.")
                }

                Section {
                    Picker("Opponents", selection: $settings.opponents) {
                        ForEach(PlayerSettings.Opponents.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Opponents")
                } footer: {
                    Text("Ghosts draws the bots faintly. Hidden bots still race you and appear on the results card.")
                }

                Section {
                    Toggle("Reduce motion", isOn: $settings.reduceMotion)
                        .disabled(systemReduceMotion)
                } footer: {
                    Text(systemReduceMotion
                         ? "On, because Reduce Motion is turned on in iOS Settings."
                         : "No screen shake, no camera zoom and no flips.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
