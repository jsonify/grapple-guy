import SpriteKit
import SwiftUI
import GrappleCore

struct ContentView: View {
    /// Levels the ⏭ button cycles through, in order. A real level select comes with #21.
    private static let levels = ["level-1", "long-swing", "test-room"]

    @State private var levelIndex = 0
    @State private var scene = GameScene(level: LevelLoader.load(ContentView.levels[0]))
    @State private var didWireScene = false
    @State private var tuning = Tuning.default
    @State private var showTuning = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SpriteView(
                scene: scene,
                preferredFramesPerSecond: 120,
                options: [.ignoresSiblingOrder],
                debugOptions: [.showsFPS]
            )
            .id(levelIndex)  // present the new scene when the level changes
            .ignoresSafeArea()

            HStack(alignment: .top, spacing: 8) {
                if showTuning {
                    TuningPanel(tuning: $tuning, onSoundCheck: { scene.soundCheck() })
                }
                Button {
                    scene.restartLevel()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel("Restart level")
                Button {
                    nextLevel()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .accessibilityLabel("Next level")
                Button(showTuning ? "Done" : "Tune") { showTuning.toggle() }
            }
            .buttonStyle(ChunkyButtonStyle())
            .padding(12)
        }
        .onChange(of: tuning) { _, newValue in
            scene.tuning = newValue
        }
        .onAppear {
            guard !didWireScene else { return }
            didWireScene = true
            scene.onContinue = { nextLevel() }
        }
    }

    private func nextLevel() {
        levelIndex = (levelIndex + 1) % Self.levels.count
        let next = GameScene(level: LevelLoader.load(Self.levels[levelIndex]))
        next.tuning = tuning
        next.onContinue = { nextLevel() }
        scene = next
    }
}

/// Chunky cartoon button: orange capsule, thick dark outline, drop shadow, squish on press.
struct ChunkyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color(red: 1.0, green: 0.55, blue: 0.13)))
            .overlay(Capsule().stroke(Color(red: 0.12, green: 0.09, blue: 0.18), lineWidth: 3))
            .shadow(color: Color(red: 0.12, green: 0.09, blue: 0.18).opacity(0.6), radius: 0, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: configuration.isPressed)
    }
}
