/// Per-level star goals (issue #18): finish, par (golf scoring, see #28), and all gems.
public enum Star: String, Codable, CaseIterable, Sendable {
    case finished
    case par
    case allGems
}

/// The score of one finished run.
public struct RunResult: Equatable, Sendable {
    public var strokes: Int
    public var time: Double
    public var gemsCollected: Int
    public var gemsTotal: Int
    public var par: Int

    public init(strokes: Int, time: Double, gemsCollected: Int, gemsTotal: Int, par: Int) {
        self.strokes = strokes
        self.time = time
        self.gemsCollected = gemsCollected
        self.gemsTotal = gemsTotal
        self.par = par
    }

    /// Finishing always earns a star. Par needs strokes at or under a positive par.
    /// A level with no gems awards the gem star automatically.
    public var stars: Set<Star> {
        var earned: Set<Star> = [.finished]
        if par > 0 && strokes <= par { earned.insert(.par) }
        if gemsCollected >= gemsTotal { earned.insert(.allGems) }
        return earned
    }

    /// Golf name for the strokes relative to par.
    public var golfTerm: String { GolfScore.term(strokes: strokes, par: par) }
}

/// The best results saved for one level.
public struct LevelRecord: Codable, Equatable, Sendable {
    public var stars: Set<Star>
    public var bestStrokes: Int?
    public var bestTime: Double?

    public init(stars: Set<Star> = [], bestStrokes: Int? = nil, bestTime: Double? = nil) {
        self.stars = stars
        self.bestStrokes = bestStrokes
        self.bestTime = bestTime
    }

    /// Stars accumulate across runs; strokes and time keep the best (lowest) values.
    public func merging(_ run: RunResult) -> LevelRecord {
        LevelRecord(
            stars: stars.union(run.stars),
            bestStrokes: min(bestStrokes ?? .max, run.strokes),
            bestTime: min(bestTime ?? .infinity, run.time)
        )
    }
}

public enum GolfScore {
    public static func term(strokes: Int, par: Int) -> String {
        if strokes == 1 { return "Hole in one!" }
        guard par > 0 else { return "\(strokes) strokes" }
        switch strokes - par {
        case ...(-3): return "Albatross!"
        case -2: return "Eagle!"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Double bogey"
        case let over: return "+\(over)"
        }
    }
}
