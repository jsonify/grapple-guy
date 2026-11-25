import Foundation

/// Something the presentation layer should react to.
public enum SimEvent: Equatable, Sendable {
    case crashed
    case finished(time: Double)
    /// The flying rope tip stuck to a grappleable surface.
    case ropeAttached(anchor: Vec2)
    /// The flying rope tip hit a non-grappleable surface.
    case ropeBlocked(at: Vec2)
    /// The flying rope tip reached the end of its range without hitting anything.
    case ropeMissed(end: Vec2)
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

    /// A rope tip in flight: launched from `origin` along `direction`, attaching to the first surface it meets.
    public struct RopeShot: Equatable, Sendable {
        public var origin: Vec2
        public var direction: Vec2
        public var traveled: Double
        public var range: Double
        public var tip: Vec2 { origin + direction * traveled }
    }

    public var tuning: Tuning
    public let level: Level
    public let fixedTimeStep: Double

    public internal(set) var position: Vec2
    public internal(set) var velocity: Vec2
    public internal(set) var rope: Rope?
    /// The rope tip while it is flying out, before it attaches, clanks or runs out.
    public internal(set) var shot: RopeShot?
    public private(set) var state: State = .playing
    /// Visual body: limbs while alive, the whole figure after a crash.
    public private(set) var ragdoll: Ragdoll
    public private(set) var elapsed: Double = 0
    private var accumulator: Double = 0
    /// How long the current rope has been held.
    private var ropeHoldTime: Double = 0
    /// Rope-shot events produced during steps, handed out by `update(deltaTime:)`.
    private var pendingEvents: [SimEvent] = []

    public init(level: Level, tuning: Tuning = .default, fixedTimeStep: Double = 1.0 / 120.0) {
        self.level = level
        self.tuning = tuning
        self.fixedTimeStep = fixedTimeStep
        position = level.spawn
        velocity = .zero
        ragdoll = Ragdoll(torso: level.spawn)
    }

    public var isRopeTaut: Bool {
        guard let rope else { return false }
        return position.distance(to: rope.anchor) >= rope.length - 0.5
    }

    public func reset() {
        position = level.spawn
        velocity = .zero
        rope = nil
        shot = nil
        pendingEvents = []
        state = .playing
        elapsed = 0
        accumulator = 0
        ragdoll.reset(torso: level.spawn)
    }

    /// Launches the rope tip toward a tapped world point: a "shot of faith" that flies out whether or not
    /// anything is there. Aim assist only bends its direction toward a reachable block.
    /// `range` overrides `tuning.ropeRange` (the scene passes a screen-relative range) but never goes below it.
    /// Returns false if no shot was launched.
    @discardableResult
    public func fireGrapple(toward target: Vec2, range: Double? = nil) -> Bool {
        guard state == .playing, rope == nil else { return false }
        let reach = max(range ?? 0, tuning.ropeRange)
        let aim = (target - position).normalized
        guard aim != .zero else { return false }
        let direction: Vec2
        switch GrappleTargeting.aim(from: position, at: target, in: level, tuning: tuning, range: reach) {
        case .attached(let anchor):
            direction = (anchor - position).normalized
        case .blocked, .missed:
            direction = aim
        }
        shot = RopeShot(origin: position, direction: direction, traveled: 0, range: reach)
        return true
    }

    /// Moves a flying rope tip; it attaches to grappleable surfaces and clanks off the rest.
    private func advanceShot(_ dt: Double) {
        guard var current = shot else { return }
        let stepLength = min(tuning.ropeTipSpeed * dt, current.range - current.traveled)
        if let hit = level.raycast(origin: current.tip, direction: current.direction, maxDistance: stepLength) {
            shot = nil
            if level.surfaces[hit.surfaceIndex].isGrappleable {
                attachRope(anchor: hit.point, length: position.distance(to: hit.point))
                applyAttachTug(toward: hit.point)
                pendingEvents.append(.ropeAttached(anchor: hit.point))
            } else {
                pendingEvents.append(.ropeBlocked(at: hit.point))
            }
            return
        }
        current.traveled += stepLength
        if current.traveled >= current.range - 1e-9 {
            shot = nil
            pendingEvents.append(.ropeMissed(end: current.tip))
        } else {
            shot = current
        }
    }

    /// Lets go of the rope. Letting go of a taut rope while rising adds `releaseLift` upward;
    /// a fast release within the angle window also adds a boost along the motion (issue #15).
    /// Returns true if the release earned the boost.
    @discardableResult
    public func release() -> Bool {
        shot = nil  // letting go cancels a rope still in flight
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

    /// Changes rope length by `delta` (negative reels in), clamped to [minRopeLength, ropeRange].
    /// On a taut rope, `momentumCarry` of the angular-momentum change applies: at 1, reeling in speeds the
    /// swing up by oldLength/newLength; at 0, tangential speed is unchanged.
    public func reel(by delta: Double, momentumCarry: Double = 1) {
        guard state == .playing, var current = rope else { return }
        let oldLength = current.length
        // Ropes attached beyond ropeRange (screen-relative shots) may stay that long but not grow.
        let newLength = min(max(oldLength + delta, tuning.minRopeLength), max(tuning.ropeRange, oldLength))
        guard newLength != oldLength else { return }
        let wasTaut = isRopeTaut
        current.length = newLength
        rope = current
        guard wasTaut else { return }
        let n = (position - current.anchor).normalized
        let t = n.perpendicular
        let speedFactor = 1 + momentumCarry * (oldLength / newLength - 1)
        velocity = n * velocity.dot(n) + t * (velocity.dot(t) * speedFactor)
        clampSpeed()
    }

    /// Holding the rope past `retractDelay` reels it in at `retractSpeed`, down to `retractMinLength` (issue #14).
    private func retractIfHeld(_ dt: Double) {
        guard let current = rope else { return }
        ropeHoldTime += dt
        guard ropeHoldTime > tuning.retractDelay else { return }
        let floor = max(tuning.retractMinLength, tuning.minRopeLength)
        guard current.length > floor else { return }
        reel(by: -min(tuning.retractSpeed * dt, current.length - floor), momentumCarry: tuning.retractMomentumCarry)
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
        ropeHoldTime = 0
    }

    /// Advances by real frame time using fixed substeps.
    @discardableResult
    public func update(deltaTime: Double) -> [SimEvent] {
        var events: [SimEvent] = []
        accumulator += min(max(deltaTime, 0), 0.25)
        while accumulator >= fixedTimeStep {
            accumulator -= fixedTimeStep
            let event = step(fixedTimeStep)
            events += pendingEvents
            pendingEvents.removeAll()
            if let event { events.append(event) }
        }
        return events
    }

    /// One fixed step. Exposed for tests.
    @discardableResult
    public func step(_ dt: Double) -> SimEvent? {
        let event = stepTorso(dt)
        ragdoll.step(dt: dt, torso: position, velocity: velocity, ropeAnchor: rope?.anchor, level: level, tuning: tuning)
        return event
    }

    private func stepTorso(_ dt: Double) -> SimEvent? {
        guard state == .playing else { return nil }
        elapsed += dt
        advanceShot(dt)
        retractIfHeld(dt)

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
        shot = nil
        ragdoll.goLimp()
        return .crashed
    }
}
