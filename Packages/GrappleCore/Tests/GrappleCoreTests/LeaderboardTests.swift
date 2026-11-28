import XCTest
@testable import GrappleCore

final class LeaderboardTests: XCTestCase {
    private func hole(_ id: String, par: Int, you: (Int, Double?), sam: (Int, Double?), pip: (Int, Double?)) -> HoleResult {
        HoleResult(hole: id, par: par, entries: [
            RaceEntry(name: "You", strokes: you.0, time: you.1, isPlayer: true),
            RaceEntry(name: "Steady Sam", strokes: sam.0, time: sam.1),
            RaceEntry(name: "Pro Pip", strokes: pip.0, time: pip.1),
        ])
    }

    func testTotalsSwingsParAndWinsOverACourse() {
        var board = Leaderboard()
        board.record(hole("h1", par: 3, you: (2, 10), sam: (3, 12), pip: (3, 9)))
        board.record(hole("h2", par: 4, you: (5, 10), sam: (4, 15), pip: (4, 14)))
        let rows = board.standings(for: ["h1", "h2"])
        XCTAssertEqual(rows.map(\.name), ["You", "Pro Pip", "Steady Sam"], "all on 7 swings, so fastest total time first")
        let you = rows.first { $0.isPlayer }!
        XCTAssertEqual(you.strokes, 7)
        XCTAssertEqual(you.toPar, 0)
        XCTAssertEqual(you.toParText, "E")
        XCTAssertEqual(you.holeWins, 1)
        XCTAssertEqual(you.holesPlayed, 2)
        XCTAssertEqual(rows[1].holeWins, 1, "Pip won hole 2 (same swings as Sam, faster)")
    }

    func testReplayingAHoleReplacesItsResult() {
        var board = Leaderboard()
        board.record(hole("h1", par: 3, you: (6, 30), sam: (3, 12), pip: (3, 9)))
        board.record(hole("h1", par: 3, you: (2, 8), sam: (3, 12), pip: (3, 9)))
        let you = board.standings().first { $0.isPlayer }!
        XCTAssertEqual(you.strokes, 2)
        XCTAssertEqual(you.toParText, "-1")
        XCTAssertEqual(board.standings().first?.name, "You")
    }

    func testPickUpsCountTheirSwingsAndRankBehindOnTies() {
        var board = Leaderboard()
        board.record(hole("h1", par: 3, you: (4, 20), sam: (4, nil), pip: (2, 9)))
        let rows = board.standings()
        XCTAssertEqual(rows.map(\.name), ["Pro Pip", "You", "Steady Sam"])
        XCTAssertEqual(rows.last?.pickUps, 1)
        XCTAssertEqual(rows.last?.toParText, "+1")
    }

    func testCourseStandingsOnlyCountThatCoursesHoles() {
        var board = Leaderboard()
        board.record(hole("a1", par: 3, you: (3, 10), sam: (3, 12), pip: (3, 9)))
        board.record(hole("b1", par: 3, you: (9, 50), sam: (3, 12), pip: (3, 9)))
        XCTAssertEqual(board.standings(for: ["a1", "a2"]).first { $0.isPlayer }?.strokes, 3)
        XCTAssertEqual(board.standings().first { $0.isPlayer }?.strokes, 12, "overall counts every course")
        board.clear(holes: ["b1"])
        XCTAssertEqual(board.standings().first { $0.isPlayer }?.strokes, 3)
    }

    func testEmptyBoardStillListsThePlayer() {
        let rows = Leaderboard().standings(for: ["h1"])
        XCTAssertEqual(rows.map(\.name), ["You"])
        XCTAssertEqual(rows[0].holesPlayed, 0)
    }

    func testRoundTripsThroughJSON() throws {
        var board = Leaderboard()
        board.record(hole("h1", par: 3, you: (2, 10), sam: (3, nil), pip: (3, 9)))
        let data = try JSONEncoder().encode(board)
        XCTAssertEqual(try JSONDecoder().decode(Leaderboard.self, from: data), board)
    }
}
