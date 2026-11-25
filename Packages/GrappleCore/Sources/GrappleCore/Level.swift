public struct Level: Codable, Sendable {
    public var name: String
    public var surfaces: [Surface]
    public var spawn: Vec2
    /// Falling below this height is a crash.
    public var killY: Double
    /// Crossing this x position finishes the level.
    public var finishX: Double

    public init(surfaces: [Surface], spawn: Vec2, killY: Double, finishX: Double, name: String = "") {
        self.name = name
        self.surfaces = surfaces
        self.spawn = spawn
        self.killY = killY
        self.finishX = finishX
    }

    /// Nearest surface hit along a ray. `direction` must be normalized.
    public func raycast(origin: Vec2, direction: Vec2, maxDistance: Double) -> RayHit? {
        var best: RayHit?
        for (index, surface) in surfaces.enumerated() {
            guard let t = surface.bounds.raycast(origin: origin, direction: direction, maxDistance: maxDistance) else { continue }
            if best.map({ t < $0.distance }) ?? true {
                best = RayHit(point: origin + direction * t, distance: t, surfaceIndex: index)
            }
        }
        return best
    }
}
