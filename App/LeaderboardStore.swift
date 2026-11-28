import Foundation
import GrappleCore

/// Saves the race leaderboard on the device: the latest result on every hole, for you and the bots.
enum LeaderboardStore {
    private static let key = "leaderboard.v1"

    static func load() -> Leaderboard {
        guard let data = UserDefaults.standard.data(forKey: key),
              let board = try? JSONDecoder().decode(Leaderboard.self, from: data)
        else { return Leaderboard() }
        return board
    }

    static func save(_ board: Leaderboard) {
        if let data = try? JSONEncoder().encode(board) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Records a finished hole. Finishing a course's first hole starts a new round of that course,
    /// so its other holes are cleared first. Returns the updated board.
    @discardableResult
    static func record(_ result: HoleResult, courseHoles: [String]) -> Leaderboard {
        var board = load()
        if courseHoles.first == result.hole { board.clear(holes: courseHoles) }
        board.record(result)
        save(board)
        return board
    }
}
