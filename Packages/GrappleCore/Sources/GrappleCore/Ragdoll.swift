/// Stick-figure body simulated as Verlet points joined by fixed-length bones (issues #12, #13).
///
/// While alive, the head, neck and pelvis (and the rope hand, when roped) are pinned to the torso;
/// arms and legs flop under gravity with a soft pull toward a rest pose. They never push back on the
/// torso, so the swing stays exactly as tuned. When limp, every point is free and keeps the momentum
/// it had, so the body tumbles on from the crash.
public struct Ragdoll: Sendable {
    public enum Joint: Int, CaseIterable, Sendable {
        case head, neck, pelvis
        case leftElbow, leftHand, rightElbow, rightHand
        case leftKnee, leftFoot, rightKnee, rightFoot
    }

    public struct Bone: Sendable {
        public let a: Joint
        public let b: Joint
        public let length: Double
    }

    public static let bones: [Bone] = [
        Bone(a: .head, b: .neck, length: Ragdoll.neckToHead),
        Bone(a: .neck, b: .pelvis, length: Ragdoll.halfSpine * 2),
        Bone(a: .neck, b: .leftElbow, length: 10), Bone(a: .leftElbow, b: .leftHand, length: 10),
        Bone(a: .neck, b: .rightElbow, length: 10), Bone(a: .rightElbow, b: .rightHand, length: 10),
        Bone(a: .pelvis, b: .leftKnee, length: 12), Bone(a: .leftKnee, b: .leftFoot, length: 12),
        Bone(a: .pelvis, b: .rightKnee, length: 12), Bone(a: .rightKnee, b: .rightFoot, length: 12),
    ]

    /// The body is drawn raised above the torso collider so the feet, not the waist, meet the ground.
    static let bodyLift = 18.0
    static let halfSpine = 13.0
    static let neckToHead = 12.0
    /// Collision radius of each joint point.
    static let pointRadius = 3.0
    /// Fraction of sliding speed lost per step while a point touches a surface.
    static let contactFriction = 0.2
    static let solverIterations = 4

    public private(set) var points: [Vec2]
    private var previous: [Vec2]
    public private(set) var isLimp = false
    /// Smoothed direction from pelvis to head while alive.
    public private(set) var up = Vec2(0, 1)

    public init(torso: Vec2) {
        points = Array(repeating: torso, count: Joint.allCases.count)
        previous = points
        reset(torso: torso)
    }

    public subscript(joint: Joint) -> Vec2 { points[joint.rawValue] }

    /// Where the rope is drawn from.
    public var ropeHand: Vec2 { self[.rightHand] }

    public mutating func reset(torso: Vec2) {
        isLimp = false
        up = Vec2(0, 1)
        points = restPose(torso: torso, up: up, ropeAnchor: nil)
        previous = points
    }

    /// Releases every pin. Pinned points were moved with the torso each step, so their momentum carries over.
    public mutating func goLimp() {
        isLimp = true
    }

    public mutating func step(dt: Double, torso: Vec2, velocity: Vec2, ropeAnchor: Vec2?, level: Level, tuning: Tuning) {
        if !isLimp {
            // Hang toward the anchor on a rope; otherwise stay mostly upright, leaning into motion.
            let targetUp = ropeAnchor.map { ($0 - torso).normalized } ?? Vec2(velocity.x * 0.0004, 1).normalized
            let blended = (up + (targetUp - up) * min(1, 12 * dt)).normalized
            up = blended == .zero ? Vec2(0, 1) : blended
        }

        let pose = restPose(torso: torso, up: up, ropeAnchor: ropeAnchor)
        let pinned = pinnedMask(roped: ropeAnchor != nil)
        let damping = max(0, 1 - tuning.limbDamping * dt)
        let gravityStep = Vec2(0, -tuning.gravity * dt * dt)
        let spring = isLimp ? 0 : min(1, tuning.limbStiffness * dt)

        for i in points.indices {
            if pinned[i] {
                previous[i] = points[i]
                points[i] = pose[i]
                continue
            }
            let velocityStep = (points[i] - previous[i]) * damping
            previous[i] = points[i]
            points[i] = points[i] + velocityStep + gravityStep
            if spring > 0 {
                points[i] = points[i] + (pose[i] - points[i]) * spring
            }
        }

        for _ in 0..<Self.solverIterations { solveBones(pinned) }
        collide(with: level, pinned: pinned)
    }

    // MARK: - Internals

    func pinnedMask(roped: Bool) -> [Bool] {
        var mask = Array(repeating: false, count: Joint.allCases.count)
        guard !isLimp else { return mask }
        mask[Joint.head.rawValue] = true
        mask[Joint.neck.rawValue] = true
        mask[Joint.pelvis.rawValue] = true
        if roped { mask[Joint.rightHand.rawValue] = true }
        return mask
    }

    /// Target position of every joint for a body centered on `torso`, pointing along `up`.
    func restPose(torso: Vec2, up: Vec2, ropeAnchor: Vec2?) -> [Vec2] {
        let down = -up
        let body = torso + up * Self.bodyLift
        let neck = body + up * Self.halfSpine
        let pelvis = body - up * Self.halfSpine

        var p = Array(repeating: Vec2.zero, count: Joint.allCases.count)
        func set(_ j: Joint, _ v: Vec2) { p[j.rawValue] = v }

        set(.neck, neck)
        set(.pelvis, pelvis)
        set(.head, neck + up * Self.neckToHead)

        let leftArm = down.rotated(by: -1.2)
        set(.leftElbow, neck + leftArm * 10)
        set(.leftHand, neck + leftArm * 20)

        let rightArm = ropeAnchor.map { ($0 - neck).normalized } ?? down.rotated(by: 1.2)
        set(.rightElbow, neck + rightArm * 10)
        set(.rightHand, neck + rightArm * 20)

        let leftLeg = down.rotated(by: -0.3)
        let rightLeg = down.rotated(by: 0.3)
        set(.leftKnee, pelvis + leftLeg * 12)
        set(.leftFoot, pelvis + leftLeg * 24)
        set(.rightKnee, pelvis + rightLeg * 12)
        set(.rightFoot, pelvis + rightLeg * 24)
        return p
    }

    private mutating func solveBones(_ pinned: [Bool]) {
        for bone in Self.bones {
            let a = bone.a.rawValue, b = bone.b.rawValue
            let delta = points[b] - points[a]
            let distance = delta.length
            guard distance > 1e-9 else { continue }
            let correction = delta * ((distance - bone.length) / distance)
            switch (pinned[a], pinned[b]) {
            case (true, true):
                continue
            case (true, false):
                points[b] = points[b] - correction
            case (false, true):
                points[a] = points[a] + correction
            case (false, false):
                points[a] = points[a] + correction * 0.5
                points[b] = points[b] - correction * 0.5
            }
        }
    }

    private mutating func collide(with level: Level, pinned: [Bool]) {
        let r = Self.pointRadius
        for i in points.indices where !pinned[i] {
            for surface in level.surfaces {
                let s = surface.bounds
                let box = AABB(x: s.lower.x - r, y: s.lower.y - r, width: s.width + 2 * r, height: s.height + 2 * r)
                guard box.contains(points[i]) else { continue }
                let face = box.nearestFace(to: points[i])
                points[i] = face.point
                // Remove motion into the surface and damp sliding along it.
                let v = points[i] - previous[i]
                let intoSurface = min(v.dot(face.normal), 0)
                let slid = (v - face.normal * intoSurface) * (1 - Self.contactFriction)
                previous[i] = points[i] - slid
            }
        }
    }
}
