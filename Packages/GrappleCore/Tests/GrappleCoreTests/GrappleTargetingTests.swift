import XCTest
@testable import GrappleCore

final class GrappleTargetingTests: XCTestCase {
    private func level(_ surfaces: [Surface]) -> Level {
        Level(surfaces: surfaces, spawn: .zero, killY: -1e9, finishX: .infinity)
    }

    private func grappleable(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Surface {
        Surface(bounds: AABB(x: x, y: y, width: w, height: h), isGrappleable: true)
    }

    private func solid(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Surface {
        Surface(bounds: AABB(x: x, y: y, width: w, height: h), isGrappleable: false)
    }

    private func anchor(aimAt target: Vec2, _ surfaces: [Surface], tuning: Tuning = .default) -> Vec2? {
        GrappleTargeting.findAnchor(from: .zero, aimAt: target, in: level(surfaces), tuning: tuning)
    }

    func testDirectHitAttachesToFirstFace() {
        let result = anchor(aimAt: Vec2(0, 100), [grappleable(-200, 500, 400, 40)])
        XCTAssertEqual(result?.x ?? .nan, 0, accuracy: 1e-9)
        XCTAssertEqual(result?.y ?? .nan, 500, accuracy: 1e-9)
    }

    func testNonGrappleableSurfaceBlocksShot() {
        let blocker = solid(-1000, 200, 2000, 50)
        XCTAssertNil(anchor(aimAt: Vec2(0, 100), [blocker, grappleable(-1000, 500, 2000, 40)]))
    }

    func testOutOfRangeMisses() {
        XCTAssertNil(anchor(aimAt: Vec2(0, 100), [grappleable(-200, 1000, 400, 40)]))
    }

    func testSnapRescuesTapNextToBlock() {
        // Direct ray toward (150, 450) passes left of the block; the tap is ~71pt from its corner.
        let block = grappleable(200, 500, 60, 40)
        let result = anchor(aimAt: Vec2(150, 450), [block])
        XCTAssertNotNil(result)
        if let result {
            XCTAssertTrue(block.bounds.contains(result) || block.bounds.closestPoint(to: result).distance(to: result) < 1)
        }
    }

    func testFanRescuesSlightlyOffAim() {
        // Aim ~14° from vertical; block sits ~27° from vertical, so ~13° off: within the 18° fan.
        let block = grappleable(300, 600, 40, 40)
        let result = anchor(aimAt: Vec2(100, 400), [block])
        XCTAssertNotNil(result)
        if let result {
            XCTAssertLessThan(block.bounds.closestPoint(to: result).distance(to: result), 1)
        }
    }

    func testFanRespectsMaxAngle() {
        // Straight up is ~27° away from the block: outside the fan, and the tap is far from it.
        XCTAssertNil(anchor(aimAt: Vec2(0, 400), [grappleable(300, 600, 40, 40)]))
    }

    func testAssistCanBeDisabled() {
        var tuning = Tuning()
        tuning.aimAssistRadius = 0
        tuning.aimAssistAngleDegrees = 0
        XCTAssertNil(anchor(aimAt: Vec2(100, 400), [grappleable(300, 600, 40, 40)], tuning: tuning))
    }

    func testTestRoomIsSwingableFromSpawn() {
        let room = Level.testRoom
        let first = GrappleTargeting.findAnchor(from: room.spawn, aimAt: room.spawn + Vec2(300, 500), in: room, tuning: .default)
        XCTAssertNotNil(first, "the first ceiling block should be reachable from the spawn")
    }
}
