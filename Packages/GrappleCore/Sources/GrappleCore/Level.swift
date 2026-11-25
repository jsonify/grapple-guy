public struct Level: Codable, Sendable {
    public var surfaces: [Surface]
    public var spawn: Vec2
    /// Falling below this height is a crash.
    public var killY: Double
    /// Crossing this x position finishes the level.
    public var finishX: Double

    public init(surfaces: [Surface], spawn: Vec2, killY: Double, finishX: Double) {
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

extension Level {
    /// Hard-coded prototype room (issue #10). Replaced by JSON level chunks in Milestone 3.
    public static let testRoom: Level = {
        var surfaces: [Surface] = []

        // Start platform.
        surfaces.append(Surface(bounds: AABB(x: -200, y: -40, width: 500, height: 40), isGrappleable: false))

        // Ceiling of grappleable blocks at varying heights.
        let heightOffsets: [Double] = [0, 60, -30, 120, 40, -60, 90, 10, 150, -20, 70, 30, 110, -40, 50, 0, 130, 20]
        for (i, dy) in heightOffsets.enumerated() {
            let x = 300 + Double(i) * 420
            surfaces.append(Surface(bounds: AABB(x: x, y: 560 + dy, width: 160, height: 40), isGrappleable: true))
        }

        // Non-grappleable obstacles.
        surfaces.append(Surface(bounds: AABB(x: 1500, y: -600, width: 80, height: 820), isGrappleable: false))  // pillar
        surfaces.append(Surface(bounds: AABB(x: 2650, y: 400, width: 320, height: 40), isGrappleable: false))   // overhang blocks shots straight up
        surfaces.append(Surface(bounds: AABB(x: 4200, y: -600, width: 80, height: 860), isGrappleable: false))  // pillar
        surfaces.append(Surface(bounds: AABB(x: 5600, y: 380, width: 60, height: 620), isGrappleable: false))   // hanging wall: go under it
        surfaces.append(Surface(bounds: AABB(x: 6600, y: -600, width: 80, height: 800), isGrappleable: false))  // pillar

        // Finish platform.
        surfaces.append(Surface(bounds: AABB(x: 7800, y: -40, width: 600, height: 40), isGrappleable: false))

        return Level(surfaces: surfaces, spawn: Vec2(0, 40), killY: -500, finishX: 7900)
    }()
}
