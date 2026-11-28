import XCTest
@testable import GrappleCore

final class RaceCountdownTests: XCTestCase {
    func testCountsThreeTwoOneThenGo() {
        var countdown = RaceCountdown(beats: 3, beatSeconds: 1)
        XCTAssertEqual(countdown.advance(0), [.beat(3)])
        XCTAssertEqual(countdown.number, 3)
        XCTAssertEqual(countdown.advance(0.5), [])
        XCTAssertEqual(countdown.advance(0.5), [.beat(2)])
        XCTAssertEqual(countdown.advance(1), [.beat(1)])
        XCTAssertTrue(countdown.isRunning)
        XCTAssertEqual(countdown.advance(1), [.go])
        XCTAssertFalse(countdown.isRunning)
        XCTAssertNil(countdown.number)
        XCTAssertEqual(countdown.advance(5), [], "nothing after GO")
    }

    func testLongStepAnnouncesEveryBeatInOrder() {
        var countdown = RaceCountdown(beats: 3, beatSeconds: 0.8)
        XCTAssertEqual(countdown.advance(10), [.beat(3), .beat(2), .beat(1), .go])
    }

    func testZeroLengthCountdownGoesStraightAway() {
        var countdown = RaceCountdown(beats: 3, beatSeconds: 0)
        XCTAssertEqual(countdown.advance(0), [.go])
        XCTAssertFalse(countdown.isRunning)
    }

    func testDurationMatchesBeats() {
        XCTAssertEqual(RaceCountdown(beats: 3, beatSeconds: 0.8).duration, 2.4, accuracy: 1e-9)
    }
}
