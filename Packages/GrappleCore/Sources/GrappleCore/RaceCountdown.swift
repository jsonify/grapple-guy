/// "3, 2, 1, GO!" before a hole starts, so the player and the bots leave together.
/// Nobody moves (and the clock doesn't run) until it reaches GO. Runs on real time, not game speed.
public struct RaceCountdown: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        /// A number appears: 3, then 2, then 1.
        case beat(Int)
        /// The race starts.
        case go
    }

    /// How many numbers are shown before GO.
    public let beats: Int
    /// Seconds each number stays up.
    public let beatSeconds: Double
    public private(set) var elapsed: Double = 0
    /// Index of the last beat announced (-1 = none yet; `beats` = GO).
    private var announced = -1

    public init(beats: Int = 3, beatSeconds: Double) {
        self.beats = max(0, beats)
        self.beatSeconds = max(0, beatSeconds)
    }

    /// Total time before GO.
    public var duration: Double { Double(beats) * beatSeconds }

    /// True until GO has been announced.
    public var isRunning: Bool { announced < beats }

    /// The number showing now (3, 2, 1), or nil once it's GO.
    public var number: Int? {
        let index = currentIndex
        return index < beats ? beats - index : nil
    }

    private var currentIndex: Int {
        guard beatSeconds > 0 else { return beats }
        return min(beats, Int((elapsed / beatSeconds).rounded(.down)))
    }

    /// Advances by `deltaTime` seconds and returns every beat crossed, in order. The first call announces
    /// the first number (even with a zero step); a long step can announce several at once.
    public mutating func advance(_ deltaTime: Double) -> [Event] {
        guard isRunning else { return [] }
        elapsed += max(0, deltaTime)
        // No beat length: no numbers to show, just go.
        guard beatSeconds > 0 else {
            announced = beats
            return [.go]
        }
        var events: [Event] = []
        while announced < currentIndex {
            announced += 1
            events.append(announced < beats ? .beat(beats - announced) : .go)
        }
        return events
    }
}
