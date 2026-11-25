import XCTest
@testable import GrappleCore

final class LevelFormatTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    private let chunksJSON = """
    [
      { "id": "start", "width": 500, "elements": [
          { "type": "solid", "rect": [0, -40, 500, 40] },
          { "type": "spawn", "at": [200, 40] } ] },
      { "id": "block", "width": 400, "elements": [
          { "type": "grapple", "rect": [100, 500, 160, 40] } ] },
      { "id": "end", "width": 300, "elements": [
          { "type": "finish", "x": 50 } ] }
    ]
    """

    private func level(_ chunks: String, library: String? = nil) throws -> Level {
        let levelJSON = #"{ "name": "T", "killY": -500, "chunks": \#(chunks) }"#
        return try LevelBuilder.load(levelData: data(levelJSON), chunkData: data(library ?? chunksJSON))
    }

    func testChunksAreLaidOutLeftToRightWithVerticalShift() throws {
        let built = try level(#"[{"id": "start"}, {"id": "block"}, {"id": "block", "dy": 60}, {"id": "end"}]"#)
        XCTAssertEqual(built.name, "T")
        XCTAssertEqual(built.killY, -500)
        XCTAssertEqual(built.spawn, Vec2(200, 40))
        XCTAssertEqual(built.finishX, 500 + 400 + 400 + 50)
        XCTAssertEqual(built.surfaces.count, 3)
        XCTAssertEqual(built.surfaces[1], Surface(bounds: AABB(x: 600, y: 500, width: 160, height: 40), isGrappleable: true))
        XCTAssertEqual(built.surfaces[2], Surface(bounds: AABB(x: 1000, y: 560, width: 160, height: 40), isGrappleable: true))
        XCTAssertFalse(built.surfaces[0].isGrappleable)
    }

    func testUnknownChunkIsReported() {
        XCTAssertThrowsError(try level(#"[{"id": "start"}, {"id": "nope"}, {"id": "end"}]"#)) {
            XCTAssertEqual($0 as? LevelLoadError, .unknownChunk("nope"))
        }
    }

    func testSpawnAndFinishAreRequiredOnce() {
        XCTAssertThrowsError(try level(#"[{"id": "block"}, {"id": "end"}]"#)) {
            XCTAssertEqual($0 as? LevelLoadError, .missingSpawn)
        }
        XCTAssertThrowsError(try level(#"[{"id": "start"}, {"id": "start"}, {"id": "end"}]"#)) {
            XCTAssertEqual($0 as? LevelLoadError, .multipleSpawns)
        }
        XCTAssertThrowsError(try level(#"[{"id": "start"}, {"id": "block"}]"#)) {
            XCTAssertEqual($0 as? LevelLoadError, .missingFinish)
        }
        XCTAssertThrowsError(try level(#"[{"id": "start"}, {"id": "end"}, {"id": "end"}]"#)) {
            XCTAssertEqual($0 as? LevelLoadError, .multipleFinishes)
        }
        XCTAssertThrowsError(try level("[]")) {
            XCTAssertEqual($0 as? LevelLoadError, .emptyLevel)
        }
    }

    func testDuplicateChunkIDIsRejected() {
        let library = #"[{"id": "a", "width": 1, "elements": []}, {"id": "a", "width": 1, "elements": []}]"#
        XCTAssertThrowsError(try ChunkLibrary.decode(data(library))) {
            XCTAssertEqual($0 as? LevelLoadError, .duplicateChunk("a"))
        }
    }

    func testBadElementsFailToDecode() {
        let badRect = #"[{"id": "a", "width": 1, "elements": [{"type": "solid", "rect": [0, 0, 10]}]}]"#
        XCTAssertThrowsError(try ChunkLibrary.decode(data(badRect)))
        let negative = #"[{"id": "a", "width": 1, "elements": [{"type": "solid", "rect": [0, 0, -10, 5]}]}]"#
        XCTAssertThrowsError(try ChunkLibrary.decode(data(negative)))
        let unknownType = #"[{"id": "a", "width": 1, "elements": [{"type": "lava", "rect": [0, 0, 10, 10]}]}]"#
        XCTAssertThrowsError(try ChunkLibrary.decode(data(unknownType)))
    }

    // MARK: Shipped level files

    /// App/Levels in the repository, found relative to this test file.
    private var levelsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // GrappleCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // GrappleCore
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("App/Levels")
    }

    func testEveryShippedLevelLoads() throws {
        let chunks = try Data(contentsOf: levelsDirectory.appendingPathComponent("chunks.json"))
        let files = try FileManager.default.contentsOfDirectory(at: levelsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "chunks.json" }
        XCTAssertFalse(files.isEmpty, "no level files found in \(levelsDirectory.path)")
        for file in files {
            XCTAssertNoThrow(try LevelBuilder.load(levelData: Data(contentsOf: file), chunkData: chunks),
                             "\(file.lastPathComponent) failed to load")
        }
    }

    func testTestRoomIsSwingableFromSpawn() throws {
        let room = try LevelBuilder.load(
            levelData: Data(contentsOf: levelsDirectory.appendingPathComponent("test-room.json")),
            chunkData: Data(contentsOf: levelsDirectory.appendingPathComponent("chunks.json")))
        let first = GrappleTargeting.findAnchor(from: room.spawn, aimAt: room.spawn + Vec2(400, 500), in: room, tuning: .default)
        XCTAssertNotNil(first, "the first ceiling block should be reachable from the spawn")
    }
}
