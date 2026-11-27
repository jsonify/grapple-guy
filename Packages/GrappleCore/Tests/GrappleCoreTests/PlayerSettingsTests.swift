import XCTest
@testable import GrappleCore

final class PlayerSettingsTests: XCTestCase {
    func testDefaultsLeaveTuningAlone() {
        XCTAssertEqual(PlayerSettings().effectiveTuning(from: .default), .default)
    }

    func testPaceScalesGameSpeed() {
        var base = Tuning()
        base.gameSpeed = 0.8
        base.paceRelaxedFactor = 0.85
        base.paceFastFactor = 1.25
        XCTAssertEqual(PlayerSettings(pace: .relaxed).effectiveTuning(from: base).gameSpeed, 0.68, accuracy: 1e-9)
        XCTAssertEqual(PlayerSettings(pace: .normal).effectiveTuning(from: base).gameSpeed, 0.8, accuracy: 1e-9)
        XCTAssertEqual(PlayerSettings(pace: .fast).effectiveTuning(from: base).gameSpeed, 1.0, accuracy: 1e-9)
    }

    func testPaceDoesNotChangePhysics() {
        // Pace only stretches time; every swing must trace the same path.
        var relaxed = PlayerSettings(pace: .relaxed).effectiveTuning(from: .default)
        relaxed.gameSpeed = Tuning.default.gameSpeed
        XCTAssertEqual(relaxed, .default)
    }

    func testReduceMotionStopsShakeZoomAndSpins() {
        for settings in [PlayerSettings(reduceMotion: true)] {
            let tuning = settings.effectiveTuning(from: .default)
            XCTAssertFalse(tuning.allowsSpins)
            XCTAssertEqual(tuning.screenShake, 0)
            XCTAssertEqual(tuning.speedZoom, 0)
        }
        let system = PlayerSettings().effectiveTuning(from: .default, systemReduceMotion: true)
        XCTAssertFalse(system.allowsSpins, "iOS Reduce Motion counts as turning it on")
    }

    func testNoSpinsEvenOnBoostedRelease() {
        var tuning = Tuning()
        tuning.allowsSpins = false
        tuning.flipMinSpeed = 300
        tuning.gravity = 0
        let sim = SwingSimulation(level: Level(surfaces: [], spawn: .zero, killY: -1e9, finishX: .infinity), tuning: tuning, seed: 1)
        sim.position = .zero
        sim.velocity = Vec2(600, 300)  // fast and 27° upward: a boosted release, which normally always spins
        sim.attachRope(anchor: Vec2(0, 500), length: 500)
        sim.release()
        XCTAssertFalse(sim.ragdoll.isSpinning)
    }

    func testRoundTripsAndToleratesOldOrUnknownValues() throws {
        let settings = PlayerSettings(pace: .fast, opponents: .hide, reduceMotion: true)
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(PlayerSettings.self, from: data), settings)

        let partial = try JSONDecoder().decode(PlayerSettings.self, from: Data(#"{"pace": "relaxed", "opponents": "neon"}"#.utf8))
        XCTAssertEqual(partial, PlayerSettings(pace: .relaxed, opponents: .ghosts, reduceMotion: false))
    }
}
