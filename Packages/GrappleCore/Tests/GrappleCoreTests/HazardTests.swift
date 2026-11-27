import XCTest
@testable import GrappleCore

final class HazardTests: XCTestCase {
    private let dt = 1.0 / 120.0

    private func run(_ sim: SwingSimulation, seconds: Double) -> [SimEvent] {
        var events: [SimEvent] = []
        for _ in 0..<Int(seconds * 120) { events += sim.update(deltaTime: dt) }
        return events
    }

    private func roof(_ x: Double, _ width: Double, top: Double = 0, sand: Bool = false) -> Surface {
        Surface(bounds: AABB(x: x, y: top - 40, width: width, height: 40), isGrappleable: false, material: sand ? .sand : .normal)
    }

    // MARK: Water and safe spot

    func testWaterCostsAStrokeAndReturnsToWhereYouLastStood() {
        // Stand on a roof at x 0…400, then fly right into water.
        let level = Level(surfaces: [roof(-200, 600)], spawn: Vec2(0, 30), killY: -1e9, finishX: .infinity,
                          water: [AABB(x: 600, y: -400, width: 400, height: 300)])
        let sim = SwingSimulation(level: level)
        _ = run(sim, seconds: 0.5)  // settle on the roof
        let stoodAt = sim.position
        XCTAssertEqual(sim.safeSpot.x, stoodAt.x, accuracy: 1)

        sim.position = Vec2(800, 0)
        sim.velocity = Vec2(0, -300)
        let events = run(sim, seconds: 1)
        XCTAssertTrue(events.contains { if case .penalty(.water, _) = $0 { return true }; return false })
        XCTAssertEqual(sim.strokes, 1)
        XCTAssertEqual(sim.position.x, stoodAt.x, accuracy: 1)
        XCTAssertEqual(sim.state, .playing)
    }

    func testCheckpointBecomesTheSafeSpot() {
        let level = Level(surfaces: [], spawn: .zero, killY: -1e9, finishX: .infinity,
                          checkpoints: [Checkpoint(position: Vec2(100, 300))])
        var tuning = Tuning()
        tuning.gravity = 0
        let sim = SwingSimulation(level: level, tuning: tuning)
        sim.velocity = Vec2(600, 0)
        _ = run(sim, seconds: 0.5)
        XCTAssertEqual(sim.safeSpot, Vec2(100, 300))
    }

    func testStandingInAPoolNeverBecomesTheSafeSpot() {
        // Pool floor at y -40, water filling it; spawn on dry roof to the left.
        let level = Level(surfaces: [roof(-300, 300), roof(0, 300, top: -40)], spawn: Vec2(-150, 30), killY: -1e9,
                          finishX: .infinity, water: [AABB(x: 0, y: -40, width: 300, height: 40)])
        let sim = SwingSimulation(level: level)
        _ = run(sim, seconds: 0.3)
        sim.position = Vec2(150, 0)
        sim.velocity = .zero
        _ = run(sim, seconds: 0.5)
        XCTAssertLessThan(sim.position.x, 0, "should be back on the dry roof, not looping in the pool")
        XCTAssertEqual(sim.penalties, 1)
    }

    // MARK: Sand

    func testSandStopsYouDead() {
        let level = Level(surfaces: [roof(-1000, 3000, sand: true)], spawn: Vec2(0, 16), killY: -1e9, finishX: .infinity)
        let sim = SwingSimulation(level: level)
        sim.velocity = Vec2(1200, -50)
        _ = run(sim, seconds: 0.25)
        XCTAssertLessThan(abs(sim.velocity.x), 30)
        XCTAssertLessThan(sim.position.x, 200, "should not slide far")
        XCTAssertTrue(sim.isInSand)
    }

    func testSandSoftensHardLandings() {
        let level = Level(surfaces: [roof(-500, 1000, sand: true)], spawn: Vec2(0, 200), killY: -1e9, finishX: .infinity)
        let sim = SwingSimulation(level: level)
        sim.velocity = Vec2(0, -(sim.tuning.crashImpactSpeed + 800))
        _ = run(sim, seconds: 0.3)
        XCTAssertEqual(sim.state, .playing)
    }

    func testRopeFromSandHasAWeakTug() {
        func speedAfterAttach(sand: Bool) -> Double {
            var tuning = Tuning()
            tuning.ropeTipSpeed = 1e9
            let pad = Surface(bounds: AABB(x: -100, y: 500, width: 200, height: 40), isGrappleable: true)
            let level = Level(surfaces: [roof(-500, 1000, sand: sand), pad], spawn: Vec2(0, 16), killY: -1e9, finishX: .infinity)
            let sim = SwingSimulation(level: level, tuning: tuning)
            _ = run(sim, seconds: 0.3)
            sim.fireGrapple(toward: Vec2(0, 500))
            sim.step(dt)
            return sim.velocity.y
        }
        let fromSand = speedAfterAttach(sand: true)
        let fromRoof = speedAfterAttach(sand: false)
        XCTAssertLessThan(fromSand, fromRoof * 0.6)
        XCTAssertGreaterThan(fromSand, 0)
    }

    // MARK: Wind

    func testWindIsPickedWithinRangeAndRepeatableBySeed() {
        let level = Level(surfaces: [], spawn: .zero, killY: -1e9, finishX: .infinity, windRange: 300)
        let winds = (0..<20).map { SwingSimulation(level: level, seed: UInt64($0)).wind }
        XCTAssertTrue(winds.allSatisfy { abs($0) <= 300 })
        XCTAssertTrue(winds.contains { $0 > 0 } && winds.contains { $0 < 0 })
        XCTAssertEqual(winds, (0..<20).map { SwingSimulation(level: level, seed: UInt64($0)).wind })
    }

    func testCalmLevelHasNoWind() {
        let level = Level(surfaces: [], spawn: .zero, killY: -1e9, finishX: .infinity)
        XCTAssertEqual(SwingSimulation(level: level).wind, 0)
    }

    func testWindPushesYouInTheAir() {
        let level = Level(surfaces: [], spawn: .zero, killY: -1e9, finishX: .infinity, windRange: 300)
        var tuning = Tuning()
        tuning.airDrag = 0
        let sim = SwingSimulation(level: level, tuning: tuning, seed: 4)
        _ = run(sim, seconds: 1)
        XCTAssertEqual(sim.velocity.x, sim.wind, accuracy: abs(sim.wind) * 0.05 + 1)
    }

    // MARK: Level format

    func testWaterSandAndWindLoadFromJSON() throws {
        let chunks = #"""
        [
          { "id": "start", "width": 500, "elements": [ { "type": "spawn", "at": [200, 40] } ] },
          { "id": "hazards", "width": 400, "elements": [
              { "type": "water", "rect": [0, -300, 400, 200] },
              { "type": "sand", "rect": [100, -40, 200, 40] } ] },
          { "id": "end", "width": 300, "elements": [ { "type": "finish", "x": 50 } ] }
        ]
        """#
        let levelJSON = #"{ "name": "H", "par": 3, "killY": -500, "wind": 250, "chunks": [{"id": "start"}, {"id": "hazards"}, {"id": "end"}] }"#
        let level = try LevelBuilder.load(levelData: Data(levelJSON.utf8), chunkData: Data(chunks.utf8))
        XCTAssertEqual(level.water, [AABB(x: 500, y: -300, width: 400, height: 200)])
        XCTAssertEqual(level.surfaces.first?.material, .sand)
        XCTAssertEqual(level.surfaces.first?.bounds, AABB(x: 600, y: -40, width: 200, height: 40))
        XCTAssertEqual(level.windRange, 250)
    }
}
