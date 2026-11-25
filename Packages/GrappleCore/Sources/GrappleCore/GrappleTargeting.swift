/// The outcome of firing the rope.
public enum GrappleShot: Equatable, Sendable {
    /// The rope stuck to a grappleable surface.
    case attached(anchor: Vec2)
    /// The shot hit a non-grappleable surface first, at this point.
    case blocked(at: Vec2)
    /// Nothing within range; `end` is where the rope ran out.
    case missed(end: Vec2)

    public var anchor: Vec2? {
        if case .attached(let anchor) = self { return anchor }
        return nil
    }
}

/// Freeform aiming with aim assist (issue #7).
public enum GrappleTargeting {
    /// Rays tried on each side of the aim direction during the fan search.
    static let fanRaysPerSide = 12

    /// Where the rope goes when the player taps `target`.
    ///
    /// 1. Direct shot: a ray from `origin` toward the tap; it sticks if the first surface hit is grappleable.
    /// 2. Near-tap snap: if the tap is within `aimAssistRadius` of a grappleable surface with a clear line, aim at it.
    /// 3. Fan: try rays at increasing angles either side of the aim and take the smallest deviation that hits a
    ///    grappleable surface. When the direct shot hit a wall, the fan widens to `aimAssistBlockedAngleDegrees`
    ///    to find a block the player *can* reach.
    /// Rope shots never pass through non-grappleable surfaces.
    public static func aim(from origin: Vec2, at target: Vec2, in level: Level, tuning: Tuning) -> GrappleShot {
        let range = tuning.ropeRange
        let aim = (target - origin).normalized
        guard aim != .zero else { return .missed(end: origin) }

        func grappleableHit(_ direction: Vec2) -> Vec2? {
            guard let hit = level.raycast(origin: origin, direction: direction, maxDistance: range),
                  level.surfaces[hit.surfaceIndex].isGrappleable else { return nil }
            return hit.point
        }

        let direct = level.raycast(origin: origin, direction: aim, maxDistance: range)
        if let direct, level.surfaces[direct.surfaceIndex].isGrappleable {
            return .attached(anchor: direct.point)
        }

        var snapped: Vec2?
        var bestSnapDistance = tuning.aimAssistRadius
        for surface in level.surfaces where surface.isGrappleable {
            let closest = surface.bounds.closestPoint(to: target)
            let d = closest.distance(to: target)
            guard d <= bestSnapDistance else { continue }
            // Aim slightly inside the box so rays toward an edge or corner don't graze past it.
            let inset = closest + (surface.bounds.center - closest).normalized
            if let point = grappleableHit((inset - origin).normalized) {
                snapped = point
                bestSnapDistance = d
            }
        }
        if let snapped { return .attached(anchor: snapped) }

        let fanDegrees = direct == nil
            ? tuning.aimAssistAngleDegrees
            : max(tuning.aimAssistAngleDegrees, tuning.aimAssistBlockedAngleDegrees)
        let maxAngle = fanDegrees * .pi / 180
        if maxAngle > 0 {
            for i in 1...fanRaysPerSide {
                let angle = maxAngle * Double(i) / Double(fanRaysPerSide)
                for sign in [1.0, -1.0] {
                    if let point = grappleableHit(aim.rotated(by: angle * sign)) {
                        return .attached(anchor: point)
                    }
                }
            }
        }

        if let direct { return .blocked(at: direct.point) }
        return .missed(end: origin + aim * range)
    }

    /// Convenience: the anchor point, or nil if the shot doesn't attach.
    public static func findAnchor(from origin: Vec2, aimAt target: Vec2, in level: Level, tuning: Tuning) -> Vec2? {
        aim(from: origin, at: target, in: level, tuning: tuning).anchor
    }
}
