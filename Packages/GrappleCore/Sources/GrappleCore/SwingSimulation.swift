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
    case gemCollected(index: Int)
    case checkpointReached(index: Int)
    /// +1 stroke; `at` is where it happened. The stickman has already been moved back.
    case penalty(reason: PenaltyReason, at: Vec2)
}

/// Golf-style penalties (issue #17): play on from a safe spot, one stroke worse.
public enum PenaltyReason: Equatable, Sendable {
    /// Fell into the street.
    case outOfBounds
    /// Landed in a water hazard.
    case water
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
    /// True while the torso touched a surface during the last step.
    public private(set) var isTouchingSurface = false
    /// True while the torso touched sand during the last step.
    public private(set) var isInSand = false
    /// Whether the rope in flight was fired from sand (weak tug).
    private var shotFromSand = false
    /// Steady horizontal wind for this hole (points/s²), picked once per simulation.
    public private(set) var wind: Double = 0
    /// Where a penalty puts you back: the last spot you stood still, or the last checkpoint, whichever is newer.
    public private(set) var safeSpot: Vec2
    /// Penalty strokes this run (already included in `strokes`).
    public private(set) var penalties = 0
    /// Drives cosmetic randomness (flips); seeded so tests are repeatable.
    private var random: SeededRandom
    /// How long the current rope has been held.
    private var ropeHoldTime: Double = 0
    /// Events produced during steps, handed out by `update(deltaTime:)`.
    private var pendingEvents: [SimEvent] = []

    /// Rope shots fired this run, including blocked and missed ones (issue #18).
    public private(set) var strokes = 0
    /// Indices into `level.gems`.
    public private(set) var collectedGems: Set<Int> = []
    /// Index into `level.checkpoints` of the last one reached.
    public private(set) var activeCheckpoint: Int?

    /// Where a crash respawns: the last checkpoint reached, or the level spawn.
    public var respawnPoint: Vec2 {
        activeCheckpoint.map { level.checkpoints[$0].position } ?? level.spawn
    }

    /// The finished run's score, once the level is finished.
    public var runResult: RunResult? {
        guard case .finished(let time) = state else { return nil }
        return RunResult(strokes: strokes, time: time, gemsCollected: collectedGems.count,
                         gemsTotal: level.gems.count, par: level.par)
    }

    /// When false, the ragdoll isn't stepped (bots' planning copies skip it for speed).
    public var simulatesRagdoll = true

    /// `wind` overrides the randomly picked wind, so every player on a hole shares the same wind.
    public init(level: Level, tuning: Tuning = .default, fixedTimeStep: Double = 1.0 / 120.0,
                seed: UInt64 = UInt64.random(in: 0...UInt64.max), wind: Double? = nil) {
        random = SeededRandom(seed: seed)
        safeSpot = level.spawn
        self.level = level
        self.tuning = tuning
        self.fixedTimeStep = fixedTimeStep
        position = level.spawn
        velocity = .zero
        ragdoll = Ragdoll(torso: level.spawn)
        if let wind {
            self.wind = wind
        } else if level.windRange > 0 {
            self.wind = Double.random(in: -level.windRange...level.windRange, using: &random)
        }
    }

    /// An independent copy of the current state, for looking ahead (bot planning).
    public func copy() -> SwingSimulation {
        let c = SwingSimulation(level: level, tuning: tuning, fixedTimeStep: fixedTimeStep, seed: 0, wind: wind)
        c.simulatesRagdoll = simulatesRagdoll
        c.position = position
        c.velocity = velocity
        c.rope = rope
        c.shot = shot
        c.state = state
        c.ragdoll = ragdoll
        c.elapsed = elapsed
        c.accumulator = accumulator
        c.isTouchingSurface = isTouchingSurface
        c.isInSand = isInSand
        c.shotFromSand = shotFromSand
        c.safeSpot = safeSpot
        c.penalties = penalties
        c.random = random
        c.ropeHoldTime = ropeHoldTime
        c.strokes = strokes
        c.collectedGems = collectedGems
        c.activeCheckpoint = activeCheckpoint
        return c
    }

    public var isRopeTaut: Bool {
        guard let rope else { return false }
        return position.distance(to: rope.anchor) >= rope.length - 0.5
    }

    /// Restarts the whole level: strokes, time, gems and checkpoints all reset.
    public func reset() {
        strokes = 0
        penalties = 0
        safeSpot = level.spawn
        collectedGems = []
        activeCheckpoint = nil
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

    /// After a crash: back to the last checkpoint. Strokes, time and gems carry over, so a crash costs strokes.
    public func respawn() {
        position = respawnPoint
        velocity = .zero
        rope = nil
        shot = nil
        pendingEvents = []
        accumulator = 0
        state = .playing
        ragdoll.reset(torso: position)
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
        shotFromSand = isInSand
        strokes += 1
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
                applyAttachTug(toward: hit.point, scale: shotFromSand ? tuning.sandTugFactor : 1)
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
        maybeFlip(boosted: boosted)
        return boosted
    }

    /// Spider-Man style: a fast upward release sometimes starts a spin; a boosted one always front-spins.
    /// Purely cosmetic: only the ragdoll rotates.
    private func maybeFlip(boosted: Bool) {
        guard tuning.allowsSpins, velocity.length >= tuning.flipMinSpeed else { return }
        guard boosted || Double.random(in: 0..<1, using: &random) < tuning.flipChance else { return }
        let front = boosted || Bool.random(using: &random)
        let travel: Double = velocity.x >= 0 ? 1 : -1
        // Moving right, a front flip turns clockwise (-1) and a back flip counter-clockwise (+1).
        ragdoll.startSpin(direction: front ? -travel : travel)
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
    func applyAttachTug(toward anchor: Vec2, scale: Double = 1) {
        let direction = (anchor - position).normalized
        let along = velocity.dot(direction)
        let tug = tuning.attachTugSpeed * scale
        if along < tug {
            velocity = velocity + direction * (tug - along)
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
        if simulatesRagdoll {
            ragdoll.step(dt: dt, torso: position, velocity: velocity, ropeAnchor: rope?.anchor, level: level, tuning: tuning,
                         spinRate: updateSpin())
        }
        return event
    }

    /// Spins last while flying free: grabbing a rope, touching a surface, crashing or finishing ends them.
    /// Faster flight spins faster, so long fast flights get several rotations.
    private func updateSpin() -> Double {
        guard ragdoll.isSpinning else { return 0 }
        guard state == .playing, rope == nil, !isTouchingSurface else {
            ragdoll.stopSpin()
            return 0
        }
        let rotationsPerSecond = min(max(velocity.length / max(1, tuning.spinSpeedPerRotation), tuning.spinMinRotations),
                                     tuning.spinMaxRotations)
        return rotationsPerSecond * 2 * .pi
    }

    private func stepTorso(_ dt: Double) -> SimEvent? {
        guard state == .playing else { return nil }
        elapsed += dt
        advanceShot(dt)
        retractIfHeld(dt)

        let gravityScale = isRopeTaut ? tuning.swingGravityMultiplier : 1
        velocity.y -= tuning.gravity * gravityScale * dt
        if !isTouchingSurface {
            velocity.x += wind * tuning.windStrength * dt
        }
        velocity = velocity * max(0, 1 - tuning.airDrag * dt)
        position = position + velocity * dt

        applyRopeConstraint()
        clampSpeed()

        if let event = resolveCollisions(dt) { return event }
        if position.y < level.killY {
            penalize(.outOfBounds)
            return nil
        }
        if level.water.contains(where: { $0.contains(position) }) {
            penalize(.water)
            return nil
        }
        collectGems()
        reachCheckpoints()
        if position.x >= level.finishX {
            state = .finished(time: elapsed)
            rope = nil
            return .finished(time: elapsed)
        }
        return nil
    }

    private func collectGems() {
        for (index, gem) in level.gems.enumerated()
        where !collectedGems.contains(index) && position.distance(to: gem) <= tuning.gemPickupRadius {
            collectedGems.insert(index)
            pendingEvents.append(.gemCollected(index: index))
        }
    }

    private func reachCheckpoints() {
        for (index, checkpoint) in level.checkpoints.enumerated()
        where position.x >= checkpoint.position.x && index > (activeCheckpoint ?? -1) {
            activeCheckpoint = index
            safeSpot = checkpoint.position
            pendingEvents.append(.checkpointReached(index: index))
        }
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
        isTouchingSurface = false
        isInSand = false
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

            let isSand = surface.material == .sand
            // Sand softens any landing; everything else crashes on a hard hit.
            if !isSand && -velocity.dot(normal) > tuning.crashImpactSpeed { return crash() }
            isTouchingSurface = true
            if isSand { isInSand = true }

            position = contact + normal * radius
            let normalSpeed = velocity.dot(normal)
            if normalSpeed < 0 { velocity = velocity - normal * normalSpeed }

            let tangent = normal.perpendicular
            let tangentSpeed = velocity.dot(tangent)
            let damped = tangentSpeed * max(0, 1 - tuning.surfaceFriction * dt)
            velocity = velocity + tangent * (damped - tangentSpeed)
            if isSand {
                velocity = velocity * max(0, 1 - tuning.sandFriction * dt)
            }

            // Standing still on top of something solid: that's where a penalty will put you back.
            if normal.y > 0.7 && velocity.length < 60 && !level.water.contains(where: { $0.contains(position) }) {
                safeSpot = position
            }
        }
        return nil
    }

    /// +1 stroke and back to the safe spot, like golf's stroke-and-distance and water-drop rules.
    private func penalize(_ reason: PenaltyReason) {
        pendingEvents.append(.penalty(reason: reason, at: position))
        strokes += 1
        penalties += 1
        position = safeSpot
        velocity = .zero
        rope = nil
        shot = nil
        ragdoll.reset(torso: position)
    }

    private func crash() -> SimEvent {
        state = .crashed
        rope = nil
        shot = nil
        ragdoll.goLimp()
        return .crashed
    }
}
