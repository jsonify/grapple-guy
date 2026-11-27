import SpriteKit
import SwiftUI
import GrappleCore

struct ContentView: View {
    /// Every hole in play order (`App/Levels/courses.json`). ⏭ and finishing a hole move to the next one.
    private static let holes = LevelLoader.holes
    /// Level names, for looking up saved stars (progress is keyed by name).
    private static let holeNames = holes.map { LevelLoader.load($0.file).name }
    private static let courseNames: [String] = holes.reduce(into: []) { names, hole in
        if names.last != hole.course { names.append(hole.course) }
    }

    @State private var levelIndex = 0
    @State private var scene = ContentView.makeScene(0)
    @State private var didWireScene = false
    /// The developer's feel numbers (Tune panel). The game runs with these plus the player's settings.
    @State private var tuning = Tuning.default
    @State private var showTuning = false
    @State private var settings = SettingsStore.load()
    @State private var showSettings = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var effectiveTuning: Tuning {
        settings.effectiveTuning(from: tuning, systemReduceMotion: systemReduceMotion)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SpriteView(
                scene: scene,
                preferredFramesPerSecond: 120,
                options: [.ignoresSiblingOrder],
                debugOptions: showTuning ? [.showsFPS] : []
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
                holePicker
                Button {
                    nextLevel()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .accessibilityLabel("Next level")
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .accessibilityLabel("Settings")
                Button(showTuning ? "Done" : "Tune") { showTuning.toggle() }
            }
            .buttonStyle(ChunkyButtonStyle())
            .padding(12)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: $settings, systemReduceMotion: systemReduceMotion)
        }
        .onChange(of: tuning) { _, _ in scene.tuning = effectiveTuning }
        .onChange(of: systemReduceMotion) { _, _ in scene.tuning = effectiveTuning }
        .onChange(of: settings) { _, newValue in
            SettingsStore.save(newValue)
            scene.tuning = effectiveTuning
            scene.opponents = newValue.opponents
        }
        .onAppear {
            guard !didWireScene else { return }
            didWireScene = true
            scene.tuning = effectiveTuning
            scene.opponents = settings.opponents
            scene.onContinue = { nextLevel() }
        }
    }

    /// Course and hole list with saved stars. A full title screen and level select come with #21.
    private var holePicker: some View {
        Menu {
            ForEach(Self.courseNames.indices, id: \.self) { course in
                Section(Self.courseNames[course]) {
                    ForEach(Self.holes.indices.filter { Self.holes[$0].courseIndex == course }, id: \.self) { index in
                        Button("\(Self.holes[index].number). \(Self.holeNames[index])   \(starText(index))") {
                            play(index)
                        }
                    }
                }
            }
        } label: {
            Text("\(Self.holes[levelIndex].courseIndex + 1)-\(Self.holes[levelIndex].number)")
        }
        .menuStyle(.button)
        .accessibilityLabel("Choose hole")
    }

    private func starText(_ index: Int) -> String {
        let stars = ProgressStore.record(for: Self.holeNames[index])?.stars.count ?? 0
        return String(repeating: "★", count: stars) + String(repeating: "☆", count: 3 - stars)
    }

    private static func makeScene(_ index: Int) -> GameScene {
        let hole = holes[index]
        let scene = GameScene(level: LevelLoader.load(hole.file))
        scene.holeLabel = "\(hole.course) · Hole \(hole.number)"
        return scene
    }

    private func nextLevel() {
        play((levelIndex + 1) % Self.holes.count)
    }

    private func play(_ index: Int) {
        guard index != levelIndex else {
            scene.restartLevel()
            return
        }
        levelIndex = index
        let next = Self.makeScene(index)
        next.tuning = effectiveTuning
        next.opponents = settings.opponents
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
