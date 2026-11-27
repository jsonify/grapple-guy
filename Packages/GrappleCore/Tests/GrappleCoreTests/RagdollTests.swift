import XCTest
@testable import GrappleCore

final class RagdollTests: XCTestCase {
    private let empty = Level(surfaces: [], spawn: .zero, killY: -1e9, finishX: .infinity)
    private let dt = 1.0 / 120.0

    private func assertBonesHoldLength(_ ragdoll: Ragdoll, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
        for bone in Ragdoll.bones {
            let length = ragdoll[bone.a].distance(to: ragdoll[bone.b])
            XCTAssertEqual(length, bone.length, accuracy: accuracy, "\(bone.a)-\(bone.b)", file: file, line: line)
        }
    }

    func testAliveSpineIsPinnedAboveTorso() {
        var ragdoll = Ragdoll(torso: .zero)
        ragdoll.step(dt: dt, torso: .zero, velocity: .zero, ropeAnchor: nil, level: empty, tuning: .default)
        XCTAssertEqual(ragdoll[.pelvis].y, 5, accuracy: 1e-9)
        XCTAssertEqual(ragdoll[.neck].y, 31, accuracy: 1e-9)
        XCTAssertEqual(ragdoll[.head].y, 43, accuracy: 1e-9)
    }

    func testBonesHoldLengthWhileMovingFast() {
        var ragdoll = Ragdoll(torso: .zero)
        var torso = Vec2.zero
        for _ in 0..<120 {
            torso = torso + Vec2(1500, 400) * dt
            ragdoll.step(dt: dt, torso: torso, velocity: Vec2(1500, 400), ropeAnchor: nil, level: empty, tuning: .default)
        }
        assertBonesHoldLength(ragdoll, accuracy: 2)
    }

    func testLimpLimbsHangUnderGravityWithoutStiffness() {
        var tuning = Tuning()
        tuning.limbStiffness = 0
        var ragdoll = Ragdoll(torso: .zero)
        for _ in 0..<240 {  // 2 s for the swinging to damp out
            ragdoll.step(dt: dt, torso: .zero, velocity: .zero, ropeAnchor: nil, level: empty, tuning: tuning)
        }
        XCTAssertLessThan(ragdoll[.leftHand].y, ragdoll[.neck].y - 15)
        XCTAssertLessThan(ragdoll[.rightHand].y, ragdoll[.neck].y - 15)
        XCTAssertLessThan(ragdoll[.leftFoot].y, ragdoll[.pelvis].y - 20)
        XCTAssertLessThan(ragdoll[.rightFoot].y, ragdoll[.pelvis].y - 20)
    }

    func testRopeHandReachesTowardAnchor() {
        var ragdoll = Ragdoll(torso: .zero)
        let anchor = Vec2(300, 500)
        for _ in 0..<60 {
            ragdoll.step(dt: dt, torso: .zero, velocity: .zero, ropeAnchor: anchor, level: empty, tuning: .default)
        }
        let arm = (ragdoll.ropeHand - ragdoll[.neck]).normalized
        let toAnchor = (anchor - ragdoll[.neck]).normalized
        XCTAssertGreaterThan(arm.dot(toAnchor), 0.99)
    }

    func testFeetStayAboveFloor() {
        let floor = Level(surfaces: [Surface(bounds: AABB(x: -500, y: -50, width: 1000, height: 50), isGrappleable: false)],
                          spawn: Vec2(0, 16), killY: -1e9, finishX: .infinity)
        var ragdoll = Ragdoll(torso: Vec2(0, 16))
        for _ in 0..<120 {
            ragdoll.step(dt: dt, torso: Vec2(0, 16), velocity: .zero, ropeAnchor: nil, level: floor, tuning: .default)
        }
        XCTAssertGreaterThanOrEqual(ragdoll[.leftFoot].y, 0)
        XCTAssertGreaterThanOrEqual(ragdoll[.rightFoot].y, 0)
    }

    func testLimpBodyKeepsMomentum() {
        var ragdoll = Ragdoll(torso: .zero)
        var torso = Vec2.zero
        for _ in 0..<30 {
            torso = torso + Vec2(1000, 0) * dt
            ragdoll.step(dt: dt, torso: torso, velocity: Vec2(1000, 0), ropeAnchor: nil, level: empty, tuning: .default)
        }
        let pelvisAtCrash = ragdoll[.pelvis].x
        ragdoll.goLimp()
        for _ in 0..<12 {  // 0.1 s; torso input is ignored once limp
            ragdoll.step(dt: dt, torso: torso, velocity: .zero, ropeAnchor: nil, level: empty, tuning: .default)
        }
        XCTAssertTrue(ragdoll.isLimp)
        XCTAssertEqual(ragdoll[.pelvis].x - pelvisAtCrash, 100, accuracy: 15)
        assertBonesHoldLength(ragdoll, accuracy: 2)
    }

    func testCrashGoesLimpAndSettlesOnFloor() {
        let floor = Surface(bounds: AABB(x: -2000, y: -50, width: 4000, height: 50), isGrappleable: false)
        let sim = SwingSimulation(level: Level(surfaces: [floor], spawn: Vec2(0, 100), killY: -1e9, finishX: .infinity))
        sim.velocity = Vec2(800, -(sim.tuning.crashImpactSpeed + 500))
        for _ in 0..<30 { sim.step(sim.fixedTimeStep) }
        XCTAssertEqual(sim.state, .crashed)
        XCTAssertTrue(sim.ragdoll.isLimp)

        for _ in 0..<600 { sim.step(sim.fixedTimeStep) }  // 5 s to tumble and settle
        let before = sim.ragdoll.points
        sim.step(sim.fixedTimeStep)
        for (i, point) in sim.ragdoll.points.enumerated() {
            XCTAssertGreaterThanOrEqual(point.y, -1, "joint \(i) sank into the floor")
            XCTAssertLessThan(point.distance(to: before[i]), 1, "joint \(i) is still moving")
        }
    }

    func testResetRestoresAlivePose() {
        let floor = Surface(bounds: AABB(x: -500, y: -150, width: 1000, height: 50), isGrappleable: false)
        let sim = SwingSimulation(level: Level(surfaces: [floor], spawn: .zero, killY: -1e9, finishX: .infinity))
        sim.velocity = Vec2(0, -(sim.tuning.crashImpactSpeed + 500))
        sim.update(deltaTime: 0.25)
        XCTAssertTrue(sim.ragdoll.isLimp)
        sim.reset()
        XCTAssertFalse(sim.ragdoll.isLimp)
        XCTAssertEqual(sim.ragdoll[.pelvis].y, 5, accuracy: 1e-9)
    }
}

final class SpinTests: XCTestCase {
    private let empty = Level(surfaces: [], spawn: .zero, killY: -1e9, finishX: .infinity)
    private let dt = 1.0 / 120.0

    func testSpinKeepsRotatingAtTheGivenRate() {
        var ragdoll = Ragdoll(torso: .zero)
        ragdoll.startSpin(direction: -1)
        // One rotation per second for 0.5 s: half a turn, upside down.
        for _ in 0..<60 {
            ragdoll.step(dt: dt, torso: .zero, velocity: .zero, ropeAnchor: nil, level: empty, tuning: .default, spinRate: 2 * .pi)
        }
        XCTAssertTrue(ragdoll.isSpinning)
        XCTAssertLessThan(ragdoll.up.y, -0.99)
        XCTAssertLessThan(ragdoll[.head].y, ragdoll[.pelvis].y)
        // Another 0.5 s: full turn, still spinning (it doesn't stop on its own).
        for _ in 0..<60 {
            ragdoll.step(dt: dt, torso: .zero, velocity: .zero, ropeAnchor: nil, level: empty, tuning: .default, spinRate: 2 * .pi)
        }
        XCTAssertTrue(ragdoll.isSpinning)
        XCTAssertGreaterThan(ragdoll.up.y, 0.99)
    }

    func testStoppingUpsideDownRotatesBackUprightWithoutSnapping() {
        var ragdoll = Ragdoll(torso: .zero)
        ragdoll.startSpin(direction: 1)
        for _ in 0..<55 {  // just short of half a turn
            ragdoll.step(dt: dt, torso: .zero, velocity: .zero, ropeAnchor: nil, level: empty, tuning: .default, spinRate: 2 * .pi)
        }
        ragdoll.stopSpin()
        var previousUp = ragdoll.up
        for _ in 0..<120 {
            ragdoll.step(dt: dt, torso: .zero, velocity: .zero, ropeAnchor: nil, level: empty, tuning: .default)
            XCTAssertGreaterThan(ragdoll.up.dot(previousUp), 0.9, "no sudden jumps while settling")
            previousUp = ragdoll.up
        }
        XCTAssertGreaterThan(ragdoll.up.y, 0.99)
    }

    func testCatchingRopeOrCrashingEndsSpin() {
        var ragdoll = Ragdoll(torso: .zero)
        ragdoll.startSpin(direction: 1)
        ragdoll.step(dt: dt, torso: .zero, velocity: .zero, ropeAnchor: Vec2(0, 500), level: empty, tuning: .default)
        XCTAssertFalse(ragdoll.isSpinning)
        ragdoll.startSpin(direction: 1)
        ragdoll.goLimp()
        XCTAssertFalse(ragdoll.isSpinning)
    }

    // MARK: Simulation control

    private func release(velocity: Vec2, chance: Double, seed: UInt64 = 1) -> SwingSimulation {
        var tuning = Tuning()
        tuning.flipChance = chance
        tuning.flipMinSpeed = 300
        // Pinned (not the defaults) so these tests check the mechanism, not today's feel numbers.
        tuning.spinSpeedPerRotation = 900
        tuning.spinMinRotations = 1.2
        tuning.spinMaxRotations = 3.5
        tuning.releaseLift = 0
        tuning.gravity = 0
        tuning.airDrag = 0
        let sim = SwingSimulation(level: empty, tuning: tuning, seed: seed)
        sim.position = .zero
        sim.velocity = velocity
        sim.attachRope(anchor: Vec2(0, 500), length: 500)
        sim.release()
        return sim
    }

    func testBoostedReleaseAlwaysFrontSpins() {
        let sim = release(velocity: Vec2(600, 300), chance: 0)  // boosted: fast, 27° upward
        XCTAssertEqual(sim.ragdoll.spinDirection, -1, "moving right, a front flip turns clockwise")
    }

    func testUnboostedReleaseSpinsOnlyByChance() {
        // 80° upward is outside the boost window.
        XCTAssertFalse(release(velocity: Vec2(100, 600), chance: 0).ragdoll.isSpinning)
        XCTAssertTrue(release(velocity: Vec2(100, 600), chance: 1).ragdoll.isSpinning)
    }

    func testSlowReleaseNeverSpins() {
        XCTAssertFalse(release(velocity: Vec2(50, 100), chance: 1).ragdoll.isSpinning)
    }

    func testFasterFlightSpinsMoreInTheSameTime() {
        func turns(speed: Double) -> Double {
            let sim = release(velocity: Vec2(speed * 0.2, speed), chance: 1)
            var total = 0.0
            var previous = sim.ragdoll.up
            for _ in 0..<60 {  // 0.5 s of free flight
                sim.step(sim.fixedTimeStep)
                total += abs(atan2(previous.cross(sim.ragdoll.up), previous.dot(sim.ragdoll.up)))
                previous = sim.ragdoll.up
            }
            return total / (2 * .pi)
        }
        let slow = turns(speed: 800)    // clamped to the 1.2/s minimum: ~0.6 turns
        let fast = turns(speed: 2700)   // 3/s: ~1.5 turns
        XCTAssertEqual(slow, 0.6, accuracy: 0.1)
        XCTAssertEqual(fast, 1.5, accuracy: 0.15)
    }

    func testSpinStopsWhenRopeAttaches() {
        let ceiling = Surface(bounds: AABB(x: -5000, y: 3000, width: 10000, height: 50), isGrappleable: true)
        var tuning = Tuning()
        tuning.flipChance = 1
        tuning.flipMinSpeed = 300
        tuning.ropeTipSpeed = 1e9
        let sim = SwingSimulation(level: Level(surfaces: [ceiling], spawn: .zero, killY: -1e9, finishX: .infinity), tuning: tuning)
        sim.velocity = Vec2(100, 800)
        sim.attachRope(anchor: Vec2(0, 800), length: 800)
        sim.position = Vec2(0, 0)
        sim.release()
        XCTAssertTrue(sim.ragdoll.isSpinning)
        sim.fireGrapple(toward: Vec2(0, 3000), range: 5000)
        sim.step(sim.fixedTimeStep)
        sim.step(sim.fixedTimeStep)
        XCTAssertFalse(sim.ragdoll.isSpinning)
    }

    func testSameSeedSameSpins() {
        let a = (0..<20).map { release(velocity: Vec2(100, 600), chance: 0.5, seed: UInt64($0)).ragdoll.spinDirection }
        let b = (0..<20).map { release(velocity: Vec2(100, 600), chance: 0.5, seed: UInt64($0)).ragdoll.spinDirection }
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.contains(nil) && (a.contains(1) || a.contains(-1)), "chance 0.5 should give a mix")
    }
}
