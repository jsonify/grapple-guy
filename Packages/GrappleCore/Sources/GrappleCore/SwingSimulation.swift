import Foundation

/// Something the presentation layer should react to.
public enum SimEvent: Equatable, Sendable {
    case crashed
    case finished(time: Double)
}

/// The stickman's torso swinging on a rope (issue #6). Pure Swift, deterministic, fixed timestep.
///
/// The torso is a point mass with a collision radius. The rope is a single length constraint:
/// when stretched it holds the torso at its length, when shorter it is slack.
public final class SwingSimulation {
    public enum State: Equatable, Sendable {
        case playing
        case crashed
        case finished(time: Double)
    }

    public struct Rope: Equatable, Sendable {
        public var anchor: Vec2
        public var length: Double
    }

    public var tuning: Tuning
    public let level: Level
    public let fixedTimeStep: Double

    public internal(set) var position: Vec2
    public internal(set) var velocity: Vec2
    public internal(set) var rope: Rope?
    public private(set) var state: State = .playing
    public private(set) var elapsed: Double = 0
    private var accumulator: Double = 0

    public init(level: Level, tuning: Tuning = .default, fixedTimeStep: Double = 1.0 / 120.0) {
        self.level = level
        self.tuning = tuning
        self.fixedTimeStep = fixedTimeStep
        position = level.spawn
        velocity = .zero
    }

    public var isRopeTaut: Bool {
        guard let rope else { return false }
        return position.distance(to: rope.anchor) >= rope.length - 0.5
    }

    public func reset() {
        position = level.spawn
        velocity = .zero
        rope = nil
        state = .playing
        elapsed = 0
        accumulator = 0
    }

    /// Fires the rope toward a tapped world point. Returns the anchor, or nil on a miss.
    @discardableResult
    public func fireGrapple(toward target: Vec2) -> Vec2? {
        guard state == .playing,
              let anchor = GrappleTargeting.findAnchor(from: position, aimAt: target, in: level, tuning: tuning)
        else { return nil }
        attachRope(anchor: anchor, length: position.distance(to: anchor))
        applyAttachTug(toward: anchor)
        return anchor
    }

    /// Lets go of the rope. Letting go of a taut rope while rising adds `releaseLift` upward;
    /// a fast release within the angle window also adds a boost along the motion (issue #15).
    /// Returns true if the release earned the boost.
    @discardableResult
    public func release() -> Bool {
        guard rope != nil else { return false }
        let wasTaut = isRopeTaut
        rope = nil
        guard state == .playing, wasTaut, velocity.y > 0 else { return false }

        let speed = velocity.length
        let angle = atan2(velocity.y, abs(velocity.x)) * 180 / .pi
        let boosted = speed >= tuning.boostMinSpeed
            && angle >= tuning.boostMinAngleDegrees
            && angle <= tuning.boostMaxAngleDegrees
        if boosted {
            velocity = velocity + velocity / speed * tuning.boostImpulse
        }
        velocity.y += tuning.releaseLift
        clampSpeed()
        return boosted
    }

    /// Changes rope length by `delta` (negative reels in), clamped to [minRopeLength, ropeRange] (issue #14).
    /// On a taut rope, angular momentum is conserved: reeling in speeds the swing up, reeling out slows it.
    public func reel(by delta: Double) {
        guard state == .playing, var current = rope else { return }
        let oldLength = current.length
        let newLength = min(max(oldLength + delta, tuning.minRopeLength), tuning.ropeRange)
        guard newLength != oldLength else { return }
        let wasTaut = isRopeTaut
        current.length = newLength
        rope = current
        guard wasTaut else { return }
        let n = (position - current.anchor).normalized
        let t = n.perpendicular
        velocity = n * velocity.dot(n) + t * (velocity.dot(t) * oldLength / newLength)
        clampSpeed()
    }

    /// Without this, a rope fired while standing (or moving slowly) is slack and nothing happens.
    func applyAttachTug(toward anchor: Vec2) {
        let direction = (anchor - position).normalized
        let along = velocity.dot(direction)
        if along < tuning.attachTugSpeed {
            velocity = velocity + direction * (tuning.attachTugSpeed - along)
        }
    }

    func attachRope(anchor: Vec2, length: Double) {
        rope = Rope(anchor: anchor, length: max(length, tuning.minRopeLength))
    }

    /// Advances by real frame time using fixed substeps.
    @discardableResult
    public func update(deltaTime: Double) -> [SimEvent] {
        var events: [SimEvent] = []
        accumulator += min(max(deltaTime, 0), 0.25)
        while accumulator >= fixedTimeStep {
            accumulator -= fixedTimeStep
            if let event = step(fixedTimeStep) { events.append(event) }
        }
        return events
    }

    /// One fixed step. Exposed for tests.
    @discardableResult
    public func step(_ dt: Double) -> SimEvent? {
        guard state == .playing else { return nil }
        elapsed += dt

        let gravityScale = isRopeTaut ? tuning.swingGravityMultiplier : 1
        velocity.y -= tuning.gravity * gravityScale * dt
        velocity = velocity * max(0, 1 - tuning.airDrag * dt)
        position = position + velocity * dt

        applyRopeConstraint()
        clampSpeed()

        if let event = resolveCollisions(dt) { return event }
        if position.y < level.killY { return crash() }
        if position.x >= level.finishX {
            state = .finished(time: elapsed)
            rope = nil
            return .finished(time: elapsed)
        }
        return nil
    }

    private func applyRopeConstraint() {
        guard let rope else { return }
        let offset = position - rope.anchor
        let distance = offset.length
        guard distance > rope.length, distance > 1e-9 else { return }  // slack
        let n = offset / distance
        position = rope.anchor + n * rope.length
        let radial = velocity.dot(n)
        if radial > 0 { velocity = velocity - n * radial }
    }

    private func clampSpeed() {
        let speed = velocity.length
        if speed > tuning.maxSpeed { velocity = velocity * (tuning.maxSpeed / speed) }
    }

    private func resolveCollisions(_ dt: Double) -> SimEvent? {
        let radius = tuning.torsoRadius
        for surface in level.surfaces {
            var contact = surface.bounds.closestPoint(to: position)
            let offset = position - contact
            let distance = offset.length
            guard distance < radius else { continue }

            let normal: Vec2
            if distance > 1e-9 {
                normal = offset / distance
            } else {
                // Torso center ended up inside the box: push out through the nearest face.
                let face = surface.bounds.nearestFace(to: position)
                contact = face.point
                normal = face.normal
            }

            if -velocity.dot(normal) > tuning.crashImpactSpeed { return crash() }

            position = contact + normal * radius
            let normalSpeed = velocity.dot(normal)
            if normalSpeed < 0 { velocity = velocity - normal * normalSpeed }

            let tangent = normal.perpendicular
            let tangentSpeed = velocity.dot(tangent)
            let damped = tangentSpeed * max(0, 1 - tuning.surfaceFriction * dt)
            velocity = velocity + tangent * (damped - tangentSpeed)
        }
        return nil
    }

    private func crash() -> SimEvent {
        state = .crashed
        rope = nil
        return .crashed
    }
}
