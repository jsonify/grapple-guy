import Foundation

// Level files (issue #16). See docs/levels.md for the authoring guide.
//
// A chunk library (`chunks.json`) defines reusable pieces in local coordinates, each with a width.
// A level file lists chunks left to right; each one starts where the previous one ended, optionally
// shifted up or down with `dy`. An endless mode can later stitch the same chunks together.

/// One thing placed inside a chunk, in chunk-local coordinates.
public enum ChunkElement: Equatable, Sendable, Decodable {
    /// Blocks the stickman and the rope. JSON: `{"type": "solid", "rect": [x, y, w, h]}`
    case solid(AABB)
    /// The rope sticks to it. JSON: `{"type": "grapple", "rect": [x, y, w, h]}`
    case grapple(AABB)
    /// Where the stickman starts. Exactly one per level. JSON: `{"type": "spawn", "at": [x, y]}`
    case spawn(Vec2)
    /// Crossing this x finishes the level. Exactly one per level. JSON: `{"type": "finish", "x": 100}`
    case finish(x: Double)
    /// A collectible. JSON: `{"type": "gem", "at": [x, y]}`
    case gem(Vec2)
    /// Crossing its x activates it; crashes then respawn here. JSON: `{"type": "checkpoint", "at": [x, y]}`
    case checkpoint(Vec2)
    /// Water hazard region: +1 penalty stroke. JSON: `{"type": "water", "rect": [x, y, w, h]}`
    case water(AABB)
    /// Sand trap surface (solid). JSON: `{"type": "sand", "rect": [x, y, w, h]}`
    case sand(AABB)

    private enum CodingKeys: String, CodingKey { case type, rect, at, x }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "solid": self = .solid(try Self.decodeRect(c))
        case "grapple": self = .grapple(try Self.decodeRect(c))
        case "spawn": self = .spawn(try Self.decodePoint(c))
        case "gem": self = .gem(try Self.decodePoint(c))
        case "checkpoint": self = .checkpoint(try Self.decodePoint(c))
        case "water": self = .water(try Self.decodeRect(c))
        case "sand": self = .sand(try Self.decodeRect(c))
        case "finish": self = .finish(x: try c.decode(Double.self, forKey: .x))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown element type \"\(type)\"")
        }
    }

    private static func decodePoint(_ c: KeyedDecodingContainer<CodingKeys>) throws -> Vec2 {
        let at = try c.decode([Double].self, forKey: .at)
        guard at.count == 2 else {
            throw DecodingError.dataCorruptedError(forKey: .at, in: c, debugDescription: "\"at\" must be [x, y]")
        }
        return Vec2(at[0], at[1])
    }

    private static func decodeRect(_ c: KeyedDecodingContainer<CodingKeys>) throws -> AABB {
        let r = try c.decode([Double].self, forKey: .rect)
        guard r.count == 4, r[2] > 0, r[3] > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .rect, in: c,
                                                   debugDescription: "rect must be [x, y, width, height] with positive size")
        }
        return AABB(x: r[0], y: r[1], width: r[2], height: r[3])
    }
}

public struct LevelChunk: Equatable, Sendable, Decodable {
    public var id: String
    /// How far the next chunk starts after this one.
    public var width: Double
    public var elements: [ChunkElement]

    public init(id: String, width: Double, elements: [ChunkElement]) {
        self.id = id
        self.width = width
        self.elements = elements
    }
}

public struct ChunkPlacement: Equatable, Sendable, Decodable {
    public var id: String
    /// Vertical shift for this placement (default 0).
    public var dy: Double?

    public init(id: String, dy: Double? = nil) {
        self.id = id
        self.dy = dy
    }
}

public struct LevelDefinition: Equatable, Sendable, Decodable {
    public var name: String
    /// Target strokes (rope shots) for the par star.
    public var par: Int
    /// Falling below this height is out of bounds (+1 stroke).
    public var killY: Double
    /// Maximum wind strength (points/s²); optional, default calm.
    public var wind: Double?
    public var chunks: [ChunkPlacement]

    public init(name: String, par: Int, killY: Double, wind: Double? = nil, chunks: [ChunkPlacement]) {
        self.name = name
        self.par = par
        self.wind = wind
        self.killY = killY
        self.chunks = chunks
    }
}

public enum LevelLoadError: Error, Equatable {
    case duplicateChunk(String)
    case invalidChunkWidth(String)
    case unknownChunk(String)
    case emptyLevel
    case missingSpawn
    case multipleSpawns
    case missingFinish
    case multipleFinishes
    case invalidPar
}

public struct ChunkLibrary: Sendable {
    public let chunks: [String: LevelChunk]

    public init(_ list: [LevelChunk]) throws {
        var byID: [String: LevelChunk] = [:]
        for chunk in list {
            guard byID[chunk.id] == nil else { throw LevelLoadError.duplicateChunk(chunk.id) }
            guard chunk.width > 0 else { throw LevelLoadError.invalidChunkWidth(chunk.id) }
            byID[chunk.id] = chunk
        }
        chunks = byID
    }

    /// Decodes a `chunks.json` file: a JSON array of chunks.
    public static func decode(_ data: Data) throws -> ChunkLibrary {
        try ChunkLibrary(JSONDecoder().decode([LevelChunk].self, from: data))
    }

    public subscript(id: String) -> LevelChunk? { chunks[id] }
}

public enum LevelBuilder {
    /// Lays the chunks out left to right and resolves them into a playable `Level`.
    public static func build(_ definition: LevelDefinition, library: ChunkLibrary) throws -> Level {
        guard !definition.chunks.isEmpty else { throw LevelLoadError.emptyLevel }
        guard definition.par > 0 else { throw LevelLoadError.invalidPar }
        var surfaces: [Surface] = []
        var gems: [Vec2] = []
        var checkpoints: [Checkpoint] = []
        var water: [AABB] = []
        var spawns: [Vec2] = []
        var finishes: [Double] = []
        var x = 0.0

        for placement in definition.chunks {
            guard let chunk = library[placement.id] else { throw LevelLoadError.unknownChunk(placement.id) }
            let offset = Vec2(x, placement.dy ?? 0)
            for element in chunk.elements {
                switch element {
                case .solid(let box): surfaces.append(Surface(bounds: box.offset(by: offset), isGrappleable: false))
                case .grapple(let box): surfaces.append(Surface(bounds: box.offset(by: offset), isGrappleable: true))
                case .spawn(let point): spawns.append(point + offset)
                case .finish(let finishX): finishes.append(finishX + offset.x)
                case .gem(let point): gems.append(point + offset)
                case .checkpoint(let point): checkpoints.append(Checkpoint(position: point + offset))
                case .water(let box): water.append(box.offset(by: offset))
                case .sand(let box): surfaces.append(Surface(bounds: box.offset(by: offset), isGrappleable: false, material: .sand))
                }
            }
            x += chunk.width
        }

        guard let spawn = spawns.first else { throw LevelLoadError.missingSpawn }
        guard spawns.count == 1 else { throw LevelLoadError.multipleSpawns }
        guard let finishX = finishes.first else { throw LevelLoadError.missingFinish }
        guard finishes.count == 1 else { throw LevelLoadError.multipleFinishes }
        return Level(surfaces: surfaces, spawn: spawn, killY: definition.killY, finishX: finishX,
                     name: definition.name, par: definition.par, gems: gems, checkpoints: checkpoints,
                     water: water, windRange: max(0, definition.wind ?? 0))
    }

    /// Decodes a level file and a chunk library and builds the level.
    public static func load(levelData: Data, chunkData: Data) throws -> Level {
        let definition = try JSONDecoder().decode(LevelDefinition.self, from: levelData)
        return try build(definition, library: ChunkLibrary.decode(chunkData))
    }
}
