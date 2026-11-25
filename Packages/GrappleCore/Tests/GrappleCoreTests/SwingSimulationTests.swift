import XCTest
@testable import GrappleCore

final class SwingSimulationTests: XCTestCase {
    private func emptyLevel(surfaces: [Surface] = [], killY: Double = -1e9, finishX: Double = .infinity) -> Level {
        Level(surfaces: surfaces, spawn: .zero, killY: killY, finishX: finishX)
    }

    private func noDrag() -> Tuning {
        var t = Tuning()
        t.airDrag = 0
        t.maxSpeed = 1e6
        return t
    }

    func testFreeFallFollowsGravity() {
        let sim = SwingSimulation(level: emptyLevel(), tuning: noDrag())
        for _ in 0..<120 { sim.step(sim.fixedTimeStep) }  // 1 second
        XCTAssertEqual(sim.position.y, -0.5 * sim.tuning.gravity, accuracy: 20)
        XCTAssertEqual(sim.position.x, 0, accuracy: 1e-9)
    }

    func testTautRopeNeverStretches() {
        let sim = SwingSimulation(level: emptyLevel(), tuning: noDrag())
        let anchor = Vec2(0, 500)
        sim.position = .zero
        sim.velocity = Vec2(600, 0)
        sim.attachRope(anchor: anchor, length: 500)
        for _ in 0..<600 {
            sim.step(sim.fixedTimeStep)
            XCTAssertLessThanOrEqual(sim.position.distance(to: anchor), 500 + 1e-6)
        }
    }

    func testSlackRopeAllowsFreeFall() {
        let sim = SwingSimulation(level: emptyLevel(), tuning: noDrag())
        let anchor = Vec2(0, 500)
        sim.attachRope(anchor: anchor, length: 500)
        sim.position = Vec2(0, 300)
        sim.velocity = .zero
        for _ in 0..<12 { sim.step(sim.fixedTimeStep) }  // 0.1 s, still well inside rope length
        XCTAssertLessThan(sim.position.distance(to: anchor), 500)
        XCTAssertFalse(sim.isRopeTaut)
        XCTAssertEqual(sim.velocity.y, -sim.tuning.gravity * 0.1, accuracy: sim.tuning.gravity * 0.1 * 0.05)
    }

    func testPendulumRoughlyConservesEnergy() {
        let tuning = noDrag()
        let sim = SwingSimulation(level: emptyLevel(), tuning: tuning)
        let length = 400.0
        sim.position = Vec2(length, 500)  // horizontal, at rest
        sim.velocity = .zero
        sim.attachRope(anchor: Vec2(0, 500), length: length)
        var fastest = 0.0
        for _ in 0..<240 {
            sim.step(sim.fixedTimeStep)
            fastest = max(fastest, sim.velocity.length)
        }
        let expected = (2 * tuning.gravity * length).squareRoot()
        XCTAssertEqual(fastest, expected, accuracy: expected * 0.05)
    }

    func testReleaseDetachesRope() {
        let sim = SwingSimulation(level: emptyLevel(), tuning: noDrag())
        sim.attachRope(anchor: Vec2(0, 500), length: 500)
        sim.release()
        XCTAssertNil(sim.rope)
    }

    func testFallingBelowKillYCrashes() {
        let sim = SwingSimulation(level: emptyLevel(killY: -100), tuning: noDrag())
        let events = sim.update(deltaTime: 0.25) + sim.update(deltaTime: 0.25)
        XCTAssertEqual(sim.state, .crashed)
        XCTAssertEqual(events, [.crashed])
    }

    func testGentleLandingDoesNotCrash() {
        let floor = Surface(bounds: AABB(x: -500, y: -50, width: 1000, height: 50), isGrappleable: false)
        let sim = SwingSimulation(level: emptyLevel(surfaces: [floor]))
        sim.position = Vec2(0, 100)
        sim.velocity = Vec2(0, -100)
        for _ in 0..<120 { sim.step(sim.fixedTimeStep) }
        XCTAssertEqual(sim.state, .playing)
        XCTAssertEqual(sim.position.y, sim.tuning.torsoRadius, accuracy: 1)
    }

    func testHardImpactCrashes() {
        let floor = Surface(bounds: AABB(x: -500, y: -50, width: 1000, height: 50), isGrappleable: false)
        let sim = SwingSimulation(level: emptyLevel(surfaces: [floor]))
        sim.position = Vec2(0, 100)
        sim.velocity = Vec2(0, -2000)
        for _ in 0..<60 { sim.step(sim.fixedTimeStep) }
        XCTAssertEqual(sim.state, .crashed)
    }

    func testCrossingFinishLineFinishes() {
        let sim = SwingSimulation(level: emptyLevel(finishX: 50), tuning: noDrag())
        sim.velocity = Vec2(200, 0)
        var events: [SimEvent] = []
        for _ in 0..<120 { if let e = sim.step(sim.fixedTimeStep) { events.append(e) } }
        guard case .finished(let time) = sim.state else { return XCTFail("expected finish, got \(sim.state)") }
        XCTAssertEqual(time, 0.25, accuracy: 0.02)
        XCTAssertEqual(events.count, 1)
    }

    func testFireGrappleAttachesAtDistance() {
        let ceiling = Surface(bounds: AABB(x: -500, y: 500, width: 1000, height: 50), isGrappleable: true)
        let sim = SwingSimulation(level: emptyLevel(surfaces: [ceiling]))
        let anchor = sim.fireGrapple(toward: Vec2(0, 1000))
        XCTAssertEqual(anchor, Vec2(0, 500))
        XCTAssertEqual(sim.rope?.length ?? 0, 500, accuracy: 1e-9)
    }

    func testGrappleFromStandingLiftsOffAndSwings() {
        let floor = Surface(bounds: AABB(x: -200, y: -40, width: 500, height: 40), isGrappleable: false)
        let block = Surface(bounds: AABB(x: 300, y: 560, width: 160, height: 40), isGrappleable: true)
        let sim = SwingSimulation(level: Level(surfaces: [floor, block], spawn: Vec2(0, 16), killY: -1e9, finishX: .infinity))
        for _ in 0..<30 { sim.step(sim.fixedTimeStep) }  // settle on the floor
        XCTAssertNotNil(sim.fireGrapple(toward: Vec2(380, 560)))
        for _ in 0..<40 { sim.step(sim.fixedTimeStep) }  // 1/3 s
        XCTAssertEqual(sim.state, .playing)
        XCTAssertGreaterThan(sim.position.y, 100, "a shot from standing should lift the stickman off the platform")
        XCTAssertGreaterThan(sim.position.x, 50, "and carry him toward the anchor")
    }

    func testAttachTugDoesNotSlowFastSwings() {
        let ceiling = Surface(bounds: AABB(x: -2000, y: 500, width: 4000, height: 50), isGrappleable: true)
        let sim = SwingSimulation(level: emptyLevel(surfaces: [ceiling]))
        sim.velocity = Vec2(0, 2000)
        sim.fireGrapple(toward: Vec2(0, 1000))
        XCTAssertEqual(sim.velocity.y, 2000, accuracy: 1e-9)
    }

    func testResetRestoresSpawn() {
        let sim = SwingSimulation(level: emptyLevel(killY: -10))
        sim.update(deltaTime: 0.25)
        XCTAssertEqual(sim.state, .crashed)
        sim.reset()
        XCTAssertEqual(sim.state, .playing)
        XCTAssertEqual(sim.position, .zero)
        XCTAssertEqual(sim.elapsed, 0)
    }
}
