/// Crossing `position.x` activates it; crashing afterwards respawns at `position`.
public struct Checkpoint: Codable, Equatable, Sendable {
    public var position: Vec2

    public init(position: Vec2) {
        self.position = position
    }
}

public struct Level: Codable, Sendable {
    public var name: String
    /// Target number of rope shots (strokes) for the par star.
    public var par: Int
    /// Collectible gem positions.
    public var gems: [Vec2]
    /// Sorted left to right.
    public var checkpoints: [Checkpoint]
    public var surfaces: [Surface]
    public var spawn: Vec2
    /// Falling below this height is a crash.
    public var killY: Double
    /// Crossing this x position finishes the level.
    public var finishX: Double

    public init(surfaces: [Surface], spawn: Vec2, killY: Double, finishX: Double, name: String = "",
                par: Int = 0, gems: [Vec2] = [], checkpoints: [Checkpoint] = []) {
        self.name = name
        self.par = par
        self.gems = gems
        self.checkpoints = checkpoints.sorted { $0.position.x < $1.position.x }
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
