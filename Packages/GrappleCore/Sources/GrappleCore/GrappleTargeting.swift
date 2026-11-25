/// Freeform aiming with aim assist (issue #7).
public enum GrappleTargeting {
    /// Rays tried on each side of the aim direction during the fan search.
    static let fanRaysPerSide = 12

    /// Where the rope should attach when the player taps `target`, or nil for a miss.
    ///
    /// 1. Direct shot: a ray from `origin` toward the tap; it sticks if the first surface hit is grappleable.
    /// 2. Near-tap snap: if the tap is within `aimAssistRadius` of a grappleable surface with a clear line, aim at it.
    /// 3. Fan: try rays at increasing angles either side of the aim; take the smallest deviation that hits a grappleable surface.
    public static func findAnchor(from origin: Vec2, aimAt target: Vec2, in level: Level, tuning: Tuning) -> Vec2? {
        let range = tuning.ropeRange
        let aim = (target - origin).normalized
        guard aim != .zero else { return nil }

        func grappleableHit(_ direction: Vec2) -> Vec2? {
            guard let hit = level.raycast(origin: origin, direction: direction, maxDistance: range),
                  level.surfaces[hit.surfaceIndex].isGrappleable else { return nil }
            return hit.point
        }

        if let point = grappleableHit(aim) { return point }

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
        if let snapped { return snapped }

        let maxAngle = tuning.aimAssistAngleDegrees * .pi / 180
        guard maxAngle > 0 else { return nil }
        for i in 1...fanRaysPerSide {
            let angle = maxAngle * Double(i) / Double(fanRaysPerSide)
            for sign in [1.0, -1.0] {
                if let point = grappleableHit(aim.rotated(by: angle * sign)) { return point }
            }
        }
        return nil
    }
}
