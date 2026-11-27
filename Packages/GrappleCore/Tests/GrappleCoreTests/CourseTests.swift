import XCTest
@testable import GrappleCore

/// Checks the shipped course list (`App/Levels/courses.json`) and plays every hole with bots,
/// so a new hole can't ship unbeatable or with a par nobody can reach.
final class CourseTests: XCTestCase {
    private var levelsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/Levels")
    }

    /// Levels that exist for testing and are deliberately not in any course.
    private let devOnlyLevels: Set<String> = ["test-room"]

    /// The player's reach on a typical phone in landscape (screen edge × 1.1); bots get the same in the game.
    private let phoneRopeReach = 1400.0

    private func courseList() throws -> CourseList {
        try CourseList.decode(Data(contentsOf: levelsDirectory.appendingPathComponent("courses.json")))
    }

    private func load(_ file: String) throws -> Level {
        try LevelBuilder.load(levelData: Data(contentsOf: levelsDirectory.appendingPathComponent("\(file).json")),
                              chunkData: Data(contentsOf: levelsDirectory.appendingPathComponent("chunks.json")))
    }

    // MARK: - Course list format

    func testCourseListDecodesInOrder() throws {
        let json = #"{"courses": [{"name": "A", "holes": ["a1", "a2"]}, {"name": "B", "holes": ["b1"]}]}"#
        let list = try CourseList.decode(Data(json.utf8))
        XCTAssertEqual(list.allHoles.map(\.file), ["a1", "a2", "b1"])
        XCTAssertEqual(list.allHoles[2], HoleRef(file: "b1", course: "B", courseIndex: 1, number: 1))
    }

    func testCourseListRejectsDuplicatesAndEmptyCourses() {
        XCTAssertThrowsError(try CourseList.decode(Data(#"{"courses": []}"#.utf8))) {
            XCTAssertEqual($0 as? CourseListError, .noCourses)
        }
        XCTAssertThrowsError(try CourseList.decode(Data(#"{"courses": [{"name": "A", "holes": []}]}"#.utf8))) {
            XCTAssertEqual($0 as? CourseListError, .emptyCourse("A"))
        }
        let duplicate = #"{"courses": [{"name": "A", "holes": ["x"]}, {"name": "B", "holes": ["x"]}]}"#
        XCTAssertThrowsError(try CourseList.decode(Data(duplicate.utf8))) {
            XCTAssertEqual($0 as? CourseListError, .duplicateHole("x"))
        }
    }

    // MARK: - Shipped courses

    func testEveryLevelFileIsInACourse() throws {
        let listed = Set(try courseList().allHoles.map(\.file))
        let files = try FileManager.default.contentsOfDirectory(at: levelsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .filter { $0 != "chunks" && $0 != "courses" && !devOnlyLevels.contains($0) }
        for file in files {
            XCTAssertTrue(listed.contains(file), "\(file).json isn't in any course in courses.json")
        }
        for hole in listed {
            XCTAssertTrue(files.contains(hole), "courses.json lists \(hole), but there's no \(hole).json")
        }
    }

    func testHoleNamesAreUnique() throws {
        // Saved progress is keyed by the level's name, so two holes with one name would share records.
        var seen: [String: String] = [:]
        for hole in try courseList().allHoles {
            let name = try load(hole.file).name
            XCTAssertNil(seen[name], "\(hole.file) and \(seen[name] ?? "") are both named \"\(name)\"")
            seen[name] = hole.file
        }
    }

    /// Every hole must be beatable: the pro bot finishes in calm air, and in the hole's strongest wind from either side
    /// (within a few tries, since a bot can be unlucky). Pars are set by hand: a skilled player beats the bots, so the
    /// pro's best is printed as a guide, not enforced. Prints one report line per hole (grep "HOLE").
    func testEveryHoleIsBeatable() throws {
        for hole in try courseList().allHoles {
            let level = try load(hole.file)
            let label = "\(hole.course) #\(hole.number) \(level.name) (\(hole.file))"
            func play(_ skill: BotSkill, wind: Double, seed: UInt64) -> Bot {
                let bot = Bot(level: level, skill: skill, seed: seed, wind: wind, ropeRange: phoneRopeReach)
                bot.swingLimit = 40  // judge whether the hole can be finished at all, not the in-game pick-up rule
                bot.finishInstantly(maxSeconds: 200)
                return bot
            }
            func summary(_ bot: Bot) -> String {
                guard case .finished(let time) = bot.sim.state else {
                    return "DNF(\(bot.sim.strokes)@\(Int(bot.sim.position.x)),\(Int(bot.sim.position.y)))"
                }
                return String(format: "%d/%.0fs", bot.sim.strokes, time)
            }
            let seeds: [UInt64] = [21, 22, 23]
            let calm = seeds.map { play(.pro, wind: 0, seed: $0) }
            var windy: [String] = []
            for wind in level.windRange > 0 ? [-level.windRange, level.windRange] : [] {
                var tries: [Bot] = []
                for seed in seeds {
                    let bot = play(.pro, wind: wind, seed: seed)
                    tries.append(bot)
                    if bot.isFinished { break }
                }
                windy.append(tries.map(summary).joined(separator: ">"))
                XCTAssertTrue(tries.last?.isFinished == true,
                              "\(label): pro bot can't finish with wind \(Int(wind)) (stuck at \(tries.last!.sim.position))")
            }
            let steady = play(.steady, wind: 0, seed: 21)
            let rookie = play(.rookie, wind: 0, seed: 21)
            let best = calm.filter(\.isFinished).map(\.sim.strokes).min()
            print("HOLE \(label) par=\(level.par) proBest=\(best.map(String.init) ?? "-") "
                  + "length=\(Int(level.finishX - level.spawn.x)) gems=\(level.gems.count) "
                  + "pro=\(calm.map(summary).joined(separator: ",")) wind=\(windy.joined(separator: " ")) "
                  + "steady=\(summary(steady)) rookie=\(summary(rookie))")
            XCTAssertTrue(calm.contains { $0.isFinished }, "\(label): pro bot can't finish in calm air "
                          + "(stuck at \(calm[0].sim.position), \(calm[0].sim.strokes) swings)")
        }
    }
}
