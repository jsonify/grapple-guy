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
        t.swingGravityMultiplier = 1
        t.releaseLift = 0
        t.retractSpeed = 0
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

    func testSwingGravityMultiplierSpeedsUpSwing() {
        var tuning = noDrag()
        tuning.swingGravityMultiplier = 2
        let sim = SwingSimulation(level: emptyLevel(), tuning: tuning)
        sim.position = Vec2(400, 500)
        sim.attachRope(anchor: Vec2(0, 500), length: 400)
        var fastest = 0.0
        for _ in 0..<240 {
            sim.step(sim.fixedTimeStep)
            fastest = max(fastest, sim.velocity.length)
        }
        let expected = (2 * 2 * tuning.gravity * 400).squareRoot()
        XCTAssertEqual(fastest, expected, accuracy: expected * 0.05)
    }

    // MARK: Reel (#14)

    private func tautSwing(velocity: Vec2) -> SwingSimulation {
        let sim = SwingSimulation(level: emptyLevel(), tuning: noDrag())
        sim.position = .zero
        sim.velocity = velocity
        sim.attachRope(anchor: Vec2(0, 500), length: 500)
        return sim
    }

    func testReelInShortensRopeAndConservesAngularMomentum() {
        let sim = tautSwing(velocity: Vec2(600, 0))
        sim.reel(by: -100)
        XCTAssertEqual(sim.rope?.length ?? 0, 400, accuracy: 1e-9)
        XCTAssertEqual(sim.velocity.x, 750, accuracy: 1e-6)
    }

    func testReelClampsToLimits() {
        let sim = tautSwing(velocity: .zero)
        sim.reel(by: -10_000)
        XCTAssertEqual(sim.rope?.length ?? 0, sim.tuning.minRopeLength, accuracy: 1e-9)
        sim.reel(by: 10_000)
        XCTAssertEqual(sim.rope?.length ?? 0, sim.tuning.ropeRange, accuracy: 1e-9)
    }

    func testReelOnSlackRopeKeepsVelocity() {
        let sim = tautSwing(velocity: Vec2(600, 0))
        sim.position = Vec2(0, 200)  // well inside rope length
        sim.reel(by: -50)
        XCTAssertEqual(sim.velocity, Vec2(600, 0))
    }

    func testPartialMomentumCarry() {
        let sim = tautSwing(velocity: Vec2(600, 0))
        sim.reel(by: -100, momentumCarry: 0.5)
        XCTAssertEqual(sim.velocity.x, 600 * 1.125, accuracy: 1e-6)
    }

    // MARK: Hold to retract (#14)

    private func heldRope(length: Double) -> SwingSimulation {
        var tuning = noDrag()
        tuning.retractSpeed = 700
        tuning.retractDelay = 0.2
        tuning.retractMinLength = 80
        let sim = SwingSimulation(level: emptyLevel(), tuning: tuning)
        sim.position = Vec2(0, 500 - length)
        sim.attachRope(anchor: Vec2(0, 500), length: length)
        return sim
    }

    func testQuickHoldDoesNotRetract() {
        let sim = heldRope(length: 500)
        for _ in 0..<12 { sim.step(sim.fixedTimeStep) }  // 0.1 s < delay
        XCTAssertEqual(sim.rope?.length ?? 0, 500, accuracy: 1e-9)
    }

    func testSustainedHoldRetractsAtSpeed() {
        let sim = heldRope(length: 500)
        for _ in 0..<60 { sim.step(sim.fixedTimeStep) }  // 0.5 s: 0.3 s of retracting
        XCTAssertEqual(sim.rope?.length ?? 0, 500 - 700 * 0.3, accuracy: 10)
    }

    func testRetractStopsAtFloor() {
        let sim = heldRope(length: 500)
        for _ in 0..<240 { sim.step(sim.fixedTimeStep) }
        XCTAssertEqual(sim.rope?.length ?? 0, 80, accuracy: 1e-9)
    }

    func testRetractNeverLengthensShortRope() {
        let sim = heldRope(length: 60)
        for _ in 0..<120 { sim.step(sim.fixedTimeStep) }
        XCTAssertEqual(sim.rope?.length ?? 0, 60, accuracy: 1e-9)
    }

    func testRetractPullsStickmanUp() {
        let sim = heldRope(length: 500)
        for _ in 0..<120 { sim.step(sim.fixedTimeStep) }
        XCTAssertGreaterThan(sim.position.y, 200)
    }

    func testReelWithoutRopeDoesNothing() {
        let sim = SwingSimulation(level: emptyLevel())
        sim.reel(by: -100)
        XCTAssertNil(sim.rope)
    }

    // MARK: Release boost (#15)

    func testWellTimedReleaseBoosts() {
        let sim = tautSwing(velocity: Vec2(600, 300))
        let before = sim.velocity.length
        XCTAssertTrue(sim.release())
        XCTAssertEqual(sim.velocity.length, before + sim.tuning.boostImpulse, accuracy: 1e-6)
        XCTAssertNil(sim.rope)
    }

    func testReleaseWhileFallingDoesNotBoost() {
        let sim = tautSwing(velocity: Vec2(600, -300))
        XCTAssertFalse(sim.release())
        XCTAssertEqual(sim.velocity, Vec2(600, -300))
    }

    func testSlowReleaseDoesNotBoost() {
        XCTAssertFalse(tautSwing(velocity: Vec2(100, 50)).release())
    }

    func testReleaseFromSlackRopeDoesNotBoost() {
        let sim = tautSwing(velocity: Vec2(600, 300))
        sim.position = Vec2(0, 200)
        XCTAssertFalse(sim.release())
    }

    func testRisingReleaseAddsLift() {
        let sim = tautSwing(velocity: Vec2(100, 50))  // too slow for the boost
        sim.tuning.releaseLift = 200
        XCTAssertFalse(sim.release())
        XCTAssertEqual(sim.velocity, Vec2(100, 250))
    }

    func testFallingReleaseGetsNoLift() {
        let sim = tautSwing(velocity: Vec2(100, -50))
        sim.tuning.releaseLift = 200
        sim.release()
        XCTAssertEqual(sim.velocity, Vec2(100, -50))
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
        sim.velocity = Vec2(0, -(sim.tuning.crashImpactSpeed + 500))
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
        var tuning = Tuning()
        tuning.ropeTipSpeed = 1e9
        let sim = SwingSimulation(level: emptyLevel(surfaces: [ceiling]), tuning: tuning)
        sim.fireGrapple(toward: Vec2(0, 1000))
        let events = sim.update(deltaTime: sim.fixedTimeStep)
        XCTAssertEqual(events, [.ropeAttached(anchor: Vec2(0, 500))])
        XCTAssertEqual(sim.rope?.anchor, Vec2(0, 500))
        XCTAssertEqual(sim.rope?.length ?? 0, 500, accuracy: 1e-9)
    }

    // MARK: Rope tip in flight ("shot of faith")

    func testRopeTipTravelsBeforeAttaching() {
        let ceiling = Surface(bounds: AABB(x: -500, y: 600, width: 1000, height: 50), isGrappleable: true)
        let sim = SwingSimulation(level: emptyLevel(surfaces: [ceiling]))  // tip speed 3000
        sim.fireGrapple(toward: Vec2(0, 1000))
        for _ in 0..<12 { sim.step(sim.fixedTimeStep) }  // 0.1 s: tip is ~300 out
        XCTAssertNil(sim.rope)
        XCTAssertEqual(sim.shot?.traveled ?? 0, 300, accuracy: 1e-6)
        var events: [SimEvent] = []
        for _ in 0..<20 { events += sim.update(deltaTime: sim.fixedTimeStep) }
        XCTAssertNotNil(sim.rope)
        XCTAssertNil(sim.shot)
        guard events.count == 1, case .ropeAttached(let anchor) = events[0] else { return XCTFail("expected one attach, got \(events)") }
        XCTAssertEqual(anchor.y, 600, accuracy: 1e-6)
    }

    func testShotOfFaithFliesFullRangeThenMisses() {
        let sim = SwingSimulation(level: emptyLevel())
        sim.fireGrapple(toward: Vec2(1, 0), range: 1500)
        var events: [SimEvent] = []
        for _ in 0..<120 { events += sim.update(deltaTime: sim.fixedTimeStep) }
        XCTAssertNil(sim.shot)
        XCTAssertNil(sim.rope)
        guard case .ropeMissed(let end) = events.first else { return XCTFail("expected a miss, got \(events)") }
        XCTAssertEqual(end.x, 1500, accuracy: 1e-6)
    }

    func testScreenRangeReachesBeyondMinimumRange() {
        let far = Surface(bounds: AABB(x: 1400, y: -100, width: 50, height: 200), isGrappleable: true)
        var tuning = noDrag()
        tuning.gravity = 0
        let sim = SwingSimulation(level: emptyLevel(surfaces: [far]), tuning: tuning)
        sim.fireGrapple(toward: Vec2(1, 0), range: 1600)
        for _ in 0..<60 { sim.step(sim.fixedTimeStep) }
        XCTAssertEqual(sim.rope?.anchor.x ?? 0, 1400, accuracy: 1e-6)
    }

    func testRangeNeverBelowMinimum() {
        let sim = SwingSimulation(level: emptyLevel())
        sim.fireGrapple(toward: Vec2(1, 0), range: 10)
        XCTAssertEqual(sim.shot?.range ?? 0, sim.tuning.ropeRange)
    }

    func testShotClanksOffWall() {
        let wall = Surface(bounds: AABB(x: -500, y: 300, width: 1000, height: 50), isGrappleable: false)
        let sim = SwingSimulation(level: emptyLevel(surfaces: [wall]))
        sim.fireGrapple(toward: Vec2(0, 1000))
        var events: [SimEvent] = []
        for _ in 0..<30 { events += sim.update(deltaTime: sim.fixedTimeStep) }
        guard events.count == 1, case .ropeBlocked(let point) = events[0] else { return XCTFail("expected one clank, got \(events)") }
        XCTAssertEqual(point.y, 300, accuracy: 1e-6)
        XCTAssertNil(sim.rope)
    }

    func testReleaseCancelsShotInFlight() {
        let sim = SwingSimulation(level: emptyLevel())
        sim.fireGrapple(toward: Vec2(0, 1000))
        sim.step(sim.fixedTimeStep)
        sim.release()
        XCTAssertNil(sim.shot)
    }

    func testRetractingLongRopeDoesNotSnapToRopeRange() {
        let sim = SwingSimulation(level: emptyLevel(), tuning: noDrag())
        sim.attachRope(anchor: Vec2(0, 1500), length: 1500)
        sim.reel(by: -10)
        XCTAssertEqual(sim.rope?.length ?? 0, 1490, accuracy: 1e-9)
    }

    func testGrappleFromStandingLiftsOffAndSwings() {
        let floor = Surface(bounds: AABB(x: -200, y: -40, width: 500, height: 40), isGrappleable: false)
        let block = Surface(bounds: AABB(x: 300, y: 560, width: 160, height: 40), isGrappleable: true)
        let sim = SwingSimulation(level: Level(surfaces: [floor, block], spawn: Vec2(0, 16), killY: -1e9, finishX: .infinity))
        for _ in 0..<30 { sim.step(sim.fixedTimeStep) }  // settle on the floor
        XCTAssertTrue(sim.fireGrapple(toward: Vec2(380, 560)))
        for _ in 0..<70 { sim.step(sim.fixedTimeStep) }  // ~0.22 s of rope flight, then ~0.36 s attached
        XCTAssertNotNil(sim.rope)
        XCTAssertEqual(sim.state, .playing)
        XCTAssertGreaterThan(sim.position.y, 100, "a shot from standing should lift the stickman off the platform")
        XCTAssertGreaterThan(sim.position.x, 50, "and carry him toward the anchor")
    }

    func testAttachTugDoesNotSlowFastSwings() {
        let ceiling = Surface(bounds: AABB(x: -2000, y: 500, width: 4000, height: 50), isGrappleable: true)
        var tuning = Tuning()
        tuning.ropeTipSpeed = 1e9  // attach on the first step
        let sim = SwingSimulation(level: emptyLevel(surfaces: [ceiling]), tuning: tuning)
        sim.velocity = Vec2(0, 2000)
        sim.fireGrapple(toward: Vec2(0, 1000))
        sim.step(sim.fixedTimeStep)
        XCTAssertNotNil(sim.rope)
        XCTAssertEqual(sim.velocity.y, 2000, accuracy: 30)  // only gravity and drag for one step
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
