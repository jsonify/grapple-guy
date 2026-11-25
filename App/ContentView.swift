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
            .buttonStyle(.borderedProminent)
            .tint(.black.opacity(0.7))
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
