import XCTest
@testable import GrappleCore

final class BotTests: XCTestCase {
    /// Start platform, a row of pads like the "ceiling" chunks, finish platform.
    private func course(pads: Int = 8, wind: Double = 0) -> Level {
        var surfaces = [Surface(bounds: AABB(x: -200, y: -40, width: 500, height: 40), isGrappleable: false)]
        let heights: [Double] = [0, 60, -30, 120, 40, -60, 90, 10, 150, -20]
        for i in 0..<pads {
            surfaces.append(Surface(bounds: AABB(x: 300 + Double(i) * 420, y: 560 + heights[i % heights.count], width: 160, height: 40),
                                    isGrappleable: true))
        }
        let end = 300 + Double(pads) * 420 + 200
        surfaces.append(Surface(bounds: AABB(x: end, y: -40, width: 600, height: 40), isGrappleable: false))
        return Level(surfaces: surfaces, spawn: Vec2(0, 40), killY: -500, finishX: end + 100, par: 4, windRange: wind)
    }

    func testCopyIsIndependent() {
        let sim = SwingSimulation(level: course(), seed: 1)
        sim.velocity = Vec2(300, 0)
        let copy = sim.copy()
        for _ in 0..<60 { copy.step(copy.fixedTimeStep) }
        XCTAssertNotEqual(copy.position, sim.position)
        XCTAssertEqual(sim.velocity, Vec2(300, 0), "the original is untouched")
        XCTAssertEqual(copy.wind, sim.wind)
    }

    func testWindOverrideIsShared() {
        let level = course(wind: 300)
        let player = SwingSimulation(level: level, seed: 9)
        let bot = Bot(level: level, skill: .steady, seed: 123, wind: player.wind, ropeRange: 1300)
        XCTAssertEqual(bot.sim.wind, player.wind)
    }

    func testProBotFinishesACourse() {
        let bot = Bot(level: course(), skill: .pro, seed: 1, wind: 0, ropeRange: 1300)
        bot.finishInstantly(maxSeconds: 90)
        XCTAssertTrue(bot.isFinished, "pro bot should reach the flag; ended at \(bot.sim.position)")
        XCTAssertLessThanOrEqual(bot.sim.strokes, 10)
    }

    func testRookieBotAlsoFinishes() {
        let bot = Bot(level: course(), skill: .rookie, seed: 2, wind: 0, ropeRange: 1300)
        bot.finishInstantly(maxSeconds: 120)
        XCTAssertTrue(bot.isFinished, "rookie should still get there; ended at \(bot.sim.position)")
    }

    func testProIsNoWorseThanRookieOverSeveralHoles() {
        var pro = 0
        var rookie = 0
        for seed in 1...4 as ClosedRange<UInt64> {
            let p = Bot(level: course(), skill: .pro, seed: seed, wind: 0, ropeRange: 1300)
            p.finishInstantly(maxSeconds: 120)
            let r = Bot(level: course(), skill: .rookie, seed: seed, wind: 0, ropeRange: 1300)
            r.finishInstantly(maxSeconds: 120)
            pro += p.sim.strokes + (p.isFinished ? 0 : 50)
            rookie += r.sim.strokes + (r.isFinished ? 0 : 50)
        }
        XCTAssertLessThanOrEqual(pro, rookie)
    }

    func testResetStartsOver() {
        let bot = Bot(level: course(), skill: .steady, seed: 3, wind: 0, ropeRange: 1300)
        for _ in 0..<120 { bot.update(deltaTime: 1.0 / 60.0) }
        XCTAssertGreaterThan(bot.sim.strokes, 0)
        bot.reset()
        XCTAssertEqual(bot.sim.strokes, 0)
        XCTAssertEqual(bot.sim.position, Vec2(0, 40))
    }

    func testBotStandingOnTopOfAPadDoesNotGrappleItsOwnPad() {
        // The bot starts on top of a pad (as when Sam landed on one): it must reach the next pads, not loop.
        var level = course()
        level.spawn = Vec2(380, 620)  // on top of the first pad (x 300…460, top 600)
        let bot = Bot(level: level, skill: .steady, seed: 5, wind: 0, ropeRange: 1300)
        bot.finishInstantly(maxSeconds: 90)
        XCTAssertTrue(bot.isFinished, "ended at \(bot.sim.position) after \(bot.sim.strokes) swings")
        XCTAssertLessThanOrEqual(bot.sim.strokes, 10)
    }

    func testBotGivesUpAtTheSwingLimit() {
        // No pads at all: nothing to do but occasional shots of faith; it must stop, not run forever.
        let level = Level(surfaces: [Surface(bounds: AABB(x: -200, y: -40, width: 500, height: 40), isGrappleable: false)],
                          spawn: Vec2(0, 40), killY: -500, finishX: 99_999, par: 3)
        let bot = Bot(level: level, skill: .pro, seed: 1, wind: 0, ropeRange: 1300)
        bot.finishInstantly(maxSeconds: 300)
        XCTAssertTrue(bot.gaveUp)
        XCTAssertLessThanOrEqual(bot.sim.strokes, bot.swingLimit)
    }

    func testBotsHandleTheShippedHazardLevel() throws {
        let levels = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("App/Levels")
        let level = try LevelBuilder.load(levelData: Data(contentsOf: levels.appendingPathComponent("rooftop-pools.json")),
                                          chunkData: Data(contentsOf: levels.appendingPathComponent("chunks.json")))
        // Steady and Pro must finish; the rookie may hit the pick-up limit on a hazard level, but should get most of the way.
        for skill in [BotSkill.steady, .pro] {
            let bot = Bot(level: level, skill: skill, seed: 11, wind: 0, ropeRange: 1500)
            bot.finishInstantly(maxSeconds: 120)
            XCTAssertTrue(bot.isFinished, "\(skill.name) didn't finish Rooftop Pools: at \(bot.sim.position), \(bot.sim.strokes) swings")
        }
        let rookie = Bot(level: level, skill: .rookie, seed: 11, wind: 0, ropeRange: 1500)
        rookie.finishInstantly(maxSeconds: 120)
        XCTAssertTrue(rookie.hasStopped, "rookie should finish or pick up, not play forever")
        XCTAssertTrue(rookie.isFinished || rookie.sim.position.x > level.finishX * 0.6,
                      "rookie stalled early: at \(rookie.sim.position), \(rookie.sim.strokes) swings")
    }

    /// Prints bot decisions for the failing scenarios so CI logs show why (no assertions).
    func testDiagnosticDecisionLogs() {
        var padTop = course()
        padTop.spawn = Vec2(380, 620)
        for (name, level, skill) in [("PADTOP", padTop, BotSkill.steady), ("COURSE", course(), BotSkill.pro)] {
            let bot = Bot(level: level, skill: skill, seed: name == "PADTOP" ? 5 : 1, wind: 0, ropeRange: 1300)
            bot.recordsDecisions = true
            bot.finishInstantly(maxSeconds: 90)
            for line in bot.decisionLog.prefix(160) { print("DIAG \(name) \(line)") }
            print("DIAG \(name) END pos=\(bot.sim.position) swings=\(bot.sim.strokes) finished=\(bot.isFinished)")
        }
    }

    func testStandingsRankFinishersBySwingsThenTime() {
        let ranked = RaceStandings.rank([
            RaceEntry(name: "slow", strokes: 3, time: 20),
            RaceEntry(name: "dnf", strokes: 1, time: nil),
            RaceEntry(name: "best", strokes: 2, time: 30),
            RaceEntry(name: "fast", strokes: 3, time: 12),
        ])
        XCTAssertEqual(ranked.map(\.name), ["best", "fast", "slow", "dnf"])
    }
}
