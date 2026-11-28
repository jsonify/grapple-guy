/// Everyone's result on one hole: the player and the bots, as the hole ended.
public struct HoleResult: Codable, Equatable, Sendable {
    /// Level file name (the hole's id in `courses.json`).
    public var hole: String
    public var par: Int
    public var entries: [RaceEntry]

    public init(hole: String, par: Int, entries: [RaceEntry]) {
        self.hole = hole
        self.par = par
        self.entries = entries
    }

    /// Who won the hole (fewest swings among finishers, then fastest), if anyone finished.
    public var winner: String? {
        RaceStandings.rank(entries).first { $0.time != nil }?.name
    }
}

/// One racer's line on the leaderboard.
public struct LeaderboardRow: Equatable, Sendable {
    public var name: String
    public var isPlayer: Bool
    /// Total swings over the holes played (a hole they gave up on counts the swings they took).
    public var strokes: Int
    /// Total swings minus total par: negative is under par.
    public var toPar: Int
    /// Total time over the holes they finished.
    public var time: Double
    public var holesPlayed: Int
    /// Holes they gave up on (golf's pick-up).
    public var pickUps: Int
    public var holeWins: Int

    /// Golf style: "E" for even, "-2", "+3".
    public var toParText: String {
        toPar == 0 ? "E" : (toPar > 0 ? "+\(toPar)" : "\(toPar)")
    }
}

/// The running stroke-play leaderboard (#32): the latest result on each hole, totalled for a course or for
/// every course. Replaying a hole replaces its result, so restarts never count twice.
public struct Leaderboard: Codable, Equatable, Sendable {
    public private(set) var results: [String: HoleResult] = [:]

    public init() {}

    public mutating func record(_ result: HoleResult) {
        results[result.hole] = result
    }

    /// Forgets these holes (e.g. starting a new round of a course).
    public mutating func clear(holes: [String]) {
        for hole in holes { results[hole] = nil }
    }

    public mutating func clearAll() {
        results = [:]
    }

    /// Results for these holes that have been played, in the given order (nil = every hole).
    public func played(_ holes: [String]? = nil) -> [HoleResult] {
        guard let holes else { return results.keys.sorted().compactMap { results[$0] } }
        return holes.compactMap { results[$0] }
    }

    /// Standings over these holes (nil = every hole played): fewest total swings first, then fewer
    /// pick-ups, then less total time. The player is listed even with nothing played yet.
    public func standings(for holes: [String]? = nil) -> [LeaderboardRow] {
        var rows: [String: LeaderboardRow] = [:]
        var order: [String] = []
        for result in played(holes) {
            let winner = result.winner
            for entry in result.entries {
                if rows[entry.name] == nil {
                    rows[entry.name] = LeaderboardRow(name: entry.name, isPlayer: entry.isPlayer, strokes: 0, toPar: 0,
                                                      time: 0, holesPlayed: 0, pickUps: 0, holeWins: 0)
                    order.append(entry.name)
                }
                rows[entry.name]!.strokes += entry.strokes
                rows[entry.name]!.toPar += entry.strokes - result.par
                rows[entry.name]!.holesPlayed += 1
                if let time = entry.time {
                    rows[entry.name]!.time += time
                } else {
                    rows[entry.name]!.pickUps += 1
                }
                if entry.name == winner { rows[entry.name]!.holeWins += 1 }
            }
        }
        if !rows.values.contains(where: \.isPlayer) {
            rows["You"] = LeaderboardRow(name: "You", isPlayer: true, strokes: 0, toPar: 0, time: 0,
                                         holesPlayed: 0, pickUps: 0, holeWins: 0)
            order.append("You")
        }
        return order.compactMap { rows[$0] }.sorted { a, b in
            if a.strokes != b.strokes { return a.strokes < b.strokes }
            if a.pickUps != b.pickUps { return a.pickUps < b.pickUps }
            return a.time < b.time
        }
    }
}
