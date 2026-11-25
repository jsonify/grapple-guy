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
        let sim = SwingSimulation(level: Level(surfaces: [], spawn: .zero, killY: -10, finishX: .infinity))
        sim.update(deltaTime: 0.25)
        XCTAssertTrue(sim.ragdoll.isLimp)
        sim.reset()
        XCTAssertFalse(sim.ragdoll.isLimp)
        XCTAssertEqual(sim.ragdoll[.pelvis].y, 5, accuracy: 1e-9)
    }
}

final class FlipTests: XCTestCase {
    private let empty = Level(surfaces: [], spawn: .zero, killY: -1e9, finishX: .infinity)
    private let dt = 1.0 / 120.0

    func testFlipTurnsBodyUpsideDownHalfwayAndBackUpright() {
        var ragdoll = Ragdoll(torso: .zero)
        ragdoll.startFlip(direction: -1, duration: 0.5)
        for _ in 0..<30 {  // halfway
            ragdoll.step(dt: dt, torso: .zero, velocity: .zero, ropeAnchor: nil, level: empty, tuning: .default)
        }
        XCTAssertTrue(ragdoll.isFlipping)
        XCTAssertLessThan(ragdoll.up.y, -0.9, "body should be upside down halfway through")
        XCTAssertLessThan(ragdoll[.head].y, ragdoll[.pelvis].y)
        for _ in 0..<40 {
            ragdoll.step(dt: dt, torso: .zero, velocity: .zero, ropeAnchor: nil, level: empty, tuning: .default)
        }
        XCTAssertFalse(ragdoll.isFlipping)
        XCTAssertGreaterThan(ragdoll.up.y, 0.9)
    }

    func testCatchingRopeEndsFlip() {
        var ragdoll = Ragdoll(torso: .zero)
        ragdoll.startFlip(direction: 1, duration: 0.5)
        ragdoll.step(dt: dt, torso: .zero, velocity: .zero, ropeAnchor: Vec2(0, 500), level: empty, tuning: .default)
        XCTAssertFalse(ragdoll.isFlipping)
    }

    func testCrashEndsFlip() {
        var ragdoll = Ragdoll(torso: .zero)
        ragdoll.startFlip(direction: 1, duration: 0.5)
        ragdoll.goLimp()
        XCTAssertFalse(ragdoll.isFlipping)
    }

    // MARK: Release triggers

    private func fastRelease(velocity: Vec2, chance: Double, seed: UInt64 = 1) -> SwingSimulation {
        var tuning = Tuning()
        tuning.flipChance = chance
        tuning.flipMinSpeed = 300
        tuning.releaseLift = 0
        let sim = SwingSimulation(level: empty, tuning: tuning, seed: seed)
        sim.position = .zero
        sim.velocity = velocity
        sim.attachRope(anchor: Vec2(0, 500), length: 500)
        sim.release()
        return sim
    }

    func testBoostedReleaseAlwaysFrontFlips() {
        let sim = fastRelease(velocity: Vec2(600, 300), chance: 0)  // boosted: fast, 27° upward
        XCTAssertTrue(sim.ragdoll.isFlipping)
        XCTAssertEqual(sim.ragdoll.flipDirection, -1, "moving right, a front flip turns clockwise")
    }

    func testUnboostedReleaseFlipsOnlyByChance() {
        // 80° upward is outside the boost window.
        XCTAssertFalse(fastRelease(velocity: Vec2(100, 600), chance: 0).ragdoll.isFlipping)
        XCTAssertTrue(fastRelease(velocity: Vec2(100, 600), chance: 1).ragdoll.isFlipping)
    }

    func testSlowReleaseNeverFlips() {
        XCTAssertFalse(fastRelease(velocity: Vec2(50, 100), chance: 1).ragdoll.isFlipping)
    }

    func testSameSeedSameFlips() {
        let a = (0..<20).map { fastRelease(velocity: Vec2(100, 600), chance: 0.5, seed: UInt64($0)).ragdoll.flipDirection }
        let b = (0..<20).map { fastRelease(velocity: Vec2(100, 600), chance: 0.5, seed: UInt64($0)).ragdoll.flipDirection }
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.contains(nil) && (a.contains(1) || a.contains(-1)), "chance 0.5 should give a mix")
    }
}
