import SpriteKit
import SwiftUI
import GrappleCore

struct ContentView: View {
    @State private var scene = GameScene(level: LevelLoader.load("test-room"))
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
            .ignoresSafeArea()

            HStack(alignment: .top, spacing: 8) {
                if showTuning {
                    TuningPanel(tuning: $tuning)
                }
                Button(showTuning ? "Done" : "Tune") { showTuning.toggle() }
                    .buttonStyle(.borderedProminent)
                    .tint(.black.opacity(0.7))
            }
            .padding(12)
        }
        .onChange(of: tuning) { _, newValue in
            scene.tuning = newValue
        }
    }
}
