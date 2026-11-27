/// Axis-aligned box, used for all level surfaces in the prototype.
public struct AABB: Equatable, Codable, Sendable {
    public var lower: Vec2
    public var upper: Vec2

    public init(x: Double, y: Double, width: Double, height: Double) {
        lower = Vec2(x, y)
        upper = Vec2(x + width, y + height)
    }

    public var width: Double { upper.x - lower.x }
    public var height: Double { upper.y - lower.y }
    public var center: Vec2 { (lower + upper) / 2 }

    public func offset(by v: Vec2) -> AABB {
        var moved = self
        moved.lower = lower + v
        moved.upper = upper + v
        return moved
    }

    public func contains(_ p: Vec2) -> Bool {
        p.x >= lower.x && p.x <= upper.x && p.y >= lower.y && p.y <= upper.y
    }

    /// Closest point on or inside the box (equals `p` when `p` is inside).
    public func closestPoint(to p: Vec2) -> Vec2 {
        Vec2(Swift.min(Swift.max(p.x, lower.x), upper.x),
             Swift.min(Swift.max(p.y, lower.y), upper.y))
    }

    /// For a point inside the box: the nearest point on its boundary and the outward normal of that face.
    public func nearestFace(to p: Vec2) -> (point: Vec2, normal: Vec2) {
        let left = p.x - lower.x, right = upper.x - p.x
        let bottom = p.y - lower.y, top = upper.y - p.y
        let m = Swift.min(left, right, bottom, top)
        if m == top { return (Vec2(p.x, upper.y), Vec2(0, 1)) }
        if m == bottom { return (Vec2(p.x, lower.y), Vec2(0, -1)) }
        if m == left { return (Vec2(lower.x, p.y), Vec2(-1, 0)) }
        return (Vec2(upper.x, p.y), Vec2(1, 0))
    }

    /// Slab-method ray cast. `direction` must be normalized.
    /// Returns the distance along the ray to the entry point, or nil if the ray misses within `maxDistance`.
    public func raycast(origin: Vec2, direction: Vec2, maxDistance: Double) -> Double? {
        var tMin = 0.0
        var tMax = maxDistance
        let axes: [(o: Double, d: Double, lo: Double, hi: Double)] = [
            (origin.x, direction.x, lower.x, upper.x),
            (origin.y, direction.y, lower.y, upper.y),
        ]
        for a in axes {
            if abs(a.d) < 1e-12 {
                if a.o < a.lo || a.o > a.hi { return nil }
            } else {
                var t1 = (a.lo - a.o) / a.d
                var t2 = (a.hi - a.o) / a.d
                if t1 > t2 { swap(&t1, &t2) }
                tMin = Swift.max(tMin, t1)
                tMax = Swift.min(tMax, t2)
                if tMin > tMax { return nil }
            }
        }
        return tMin
    }
}

public enum SurfaceMaterial: String, Codable, Sendable {
    case normal
    /// Sand trap: stops you dead, softens landings, and weakens the next rope tug (issue #17).
    case sand
}

public struct Surface: Equatable, Codable, Sendable {
    public var bounds: AABB
    /// Whether the rope can stick to this surface. Non-grappleable surfaces still block rope shots.
    public var isGrappleable: Bool
    public var material: SurfaceMaterial

    public init(bounds: AABB, isGrappleable: Bool, material: SurfaceMaterial = .normal) {
        self.bounds = bounds
        self.isGrappleable = isGrappleable
        self.material = material
    }
}

public struct RayHit: Equatable, Sendable {
    public var point: Vec2
    public var distance: Double
    public var surfaceIndex: Int
}
