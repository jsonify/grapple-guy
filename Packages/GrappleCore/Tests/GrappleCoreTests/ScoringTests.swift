import XCTest
@testable import GrappleCore

final class ScoringTests: XCTestCase {
    private func run(strokes: Int, par: Int = 10, gems: Int = 3, of total: Int = 3, time: Double = 30) -> RunResult {
        RunResult(strokes: strokes, time: time, gemsCollected: gems, gemsTotal: total, par: par)
    }

    func testAllThreeStars() {
        XCTAssertEqual(run(strokes: 10).stars, [.finished, .par, .allGems])
    }

    func testOverParAndMissingGems() {
        XCTAssertEqual(run(strokes: 11, gems: 2).stars, [.finished])
    }

    func testLevelWithoutGemsAwardsGemStar() {
        XCTAssertTrue(run(strokes: 20, gems: 0, of: 0).stars.contains(.allGems))
    }

    func testNoParMeansNoParStar() {
        XCTAssertFalse(run(strokes: 1, par: 0).stars.contains(.par))
    }

    func testGolfTerms() {
        XCTAssertEqual(GolfScore.term(strokes: 1, par: 4), "Hole in one!")
        XCTAssertEqual(GolfScore.term(strokes: 7, par: 10), "Albatross!")
        XCTAssertEqual(GolfScore.term(strokes: 8, par: 10), "Eagle!")
        XCTAssertEqual(GolfScore.term(strokes: 9, par: 10), "Birdie")
        XCTAssertEqual(GolfScore.term(strokes: 10, par: 10), "Par")
        XCTAssertEqual(GolfScore.term(strokes: 11, par: 10), "Bogey")
        XCTAssertEqual(GolfScore.term(strokes: 12, par: 10), "Double bogey")
        XCTAssertEqual(GolfScore.term(strokes: 15, par: 10), "+5")
    }

    func testRecordKeepsBestsAndAccumulatesStars() {
        var record = LevelRecord()
        record = record.merging(run(strokes: 12, gems: 3, time: 40))   // finished + gems
        record = record.merging(run(strokes: 9, gems: 1, time: 50))    // finished + par
        XCTAssertEqual(record.stars, [.finished, .par, .allGems])
        XCTAssertEqual(record.bestStrokes, 9)
        XCTAssertEqual(record.bestTime, 40)
    }

    func testRecordRoundTripsThroughJSON() throws {
        let record = LevelRecord(stars: [.finished, .par], bestStrokes: 7, bestTime: 12.5)
        let decoded = try JSONDecoder().decode(LevelRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded, record)
    }

    // MARK: Simulation bookkeeping

    private func sim(gems: [Vec2] = [], checkpoints: [Checkpoint] = [], killY: Double = -1e9, finishX: Double = .infinity) -> SwingSimulation {
        var tuning = Tuning()
        tuning.gravity = 0
        tuning.airDrag = 0
        let level = Level(surfaces: [], spawn: .zero, killY: killY, finishX: finishX, par: 3, gems: gems, checkpoints: checkpoints)
        return SwingSimulation(level: level, tuning: tuning)
    }

    func testEveryShotIsAStrokeEvenMisses() {
        let s = sim()
        s.fireGrapple(toward: Vec2(1, 0))
        s.release()
        s.fireGrapple(toward: Vec2(0, 1))
        XCTAssertEqual(s.strokes, 2)
        s.reset()
        XCTAssertEqual(s.strokes, 0)
    }

    func testGemIsCollectedOnceWhenPassed() {
        let s = sim(gems: [Vec2(100, 0)])
        s.velocity = Vec2(600, 0)
        var events: [SimEvent] = []
        for _ in 0..<60 { events += s.update(deltaTime: s.fixedTimeStep) }
        XCTAssertEqual(events.filter { $0 == .gemCollected(index: 0) }.count, 1)
        XCTAssertEqual(s.collectedGems, [0])
    }

    func testCheckpointRespawnKeepsStrokesGemsAndTime() {
        let s = sim(gems: [Vec2(100, 0)], checkpoints: [Checkpoint(position: Vec2(200, 50))], killY: -1e9)
        s.velocity = Vec2(600, 0)
        s.fireGrapple(toward: Vec2(1, 1))
        var events: [SimEvent] = []
        for _ in 0..<60 { events += s.update(deltaTime: s.fixedTimeStep) }
        XCTAssertTrue(events.contains(.checkpointReached(index: 0)))
        XCTAssertEqual(s.activeCheckpoint, 0)
        let elapsed = s.elapsed

        s.respawn()
        XCTAssertEqual(s.position, Vec2(200, 50))
        XCTAssertEqual(s.velocity, .zero)
        XCTAssertEqual(s.state, .playing)
        XCTAssertEqual(s.strokes, 1)
        XCTAssertEqual(s.collectedGems, [0])
        XCTAssertEqual(s.elapsed, elapsed)

        s.reset()
        XCTAssertNil(s.activeCheckpoint)
        XCTAssertEqual(s.position, .zero)
        XCTAssertTrue(s.collectedGems.isEmpty)
    }

    func testRunResultWhenFinished() {
        let s = sim(gems: [Vec2(100, 0), Vec2(5000, 0)], finishX: 300)
        s.velocity = Vec2(600, 0)
        s.fireGrapple(toward: Vec2(1, 0))
        XCTAssertNil(s.runResult)
        for _ in 0..<120 { s.update(deltaTime: s.fixedTimeStep) }
        let result = try? XCTUnwrap(s.runResult)
        XCTAssertEqual(result?.strokes, 1)
        XCTAssertEqual(result?.gemsCollected, 1)
        XCTAssertEqual(result?.gemsTotal, 2)
        XCTAssertEqual(result?.stars, [.finished, .par])
        XCTAssertEqual(result?.golfTerm, "Hole in one!")
    }
}
