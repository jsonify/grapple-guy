/// Choices the player makes in the settings sheet (#36), saved on the device.
/// `Tuning` holds the developer's feel numbers; `effectiveTuning(from:)` layers these choices on top.
public struct PlayerSettings: Equatable, Codable, Sendable {
    /// How fast the game runs. Bots share the player's clock, so races stay fair at every pace.
    public enum Pace: String, Codable, CaseIterable, Sendable {
        case relaxed, normal, fast

        public var title: String {
            switch self {
            case .relaxed: return "Relaxed"
            case .normal: return "Normal"
            case .fast: return "Fast"
            }
        }
    }

    /// How the bots racing you are drawn. Hidden bots still race and still appear on the results card.
    public enum Opponents: String, Codable, CaseIterable, Sendable {
        case show, ghosts, hide

        public var title: String {
            switch self {
            case .show: return "Show"
            case .ghosts: return "Ghosts"
            case .hide: return "Hide"
            }
        }
    }

    public var pace: Pace = .normal
    public var opponents: Opponents = .ghosts
    /// No screen shake, no speed zoom and no spins.
    public var reduceMotion: Bool = false

    public init(pace: Pace = .normal, opponents: Opponents = .ghosts, reduceMotion: Bool = false) {
        self.pace = pace
        self.opponents = opponents
        self.reduceMotion = reduceMotion
    }

    /// The tuning the game actually runs with: the developer's `base` with these choices applied.
    /// `systemReduceMotion` is iOS's own Reduce Motion setting, which counts as if the player had turned it on.
    public func effectiveTuning(from base: Tuning, systemReduceMotion: Bool = false) -> Tuning {
        var tuning = base
        switch pace {
        case .relaxed: tuning.gameSpeed = base.gameSpeed * base.paceRelaxedFactor
        case .normal: break
        case .fast: tuning.gameSpeed = base.gameSpeed * base.paceFastFactor
        }
        if reduceMotion || systemReduceMotion {
            tuning.allowsSpins = false
            tuning.screenShake = 0
            tuning.speedZoom = 0
        }
        return tuning
    }

    // Decode field by field so settings saved by an older build (or with a removed option) still load.
    private enum CodingKeys: String, CodingKey { case pace, opponents, reduceMotion }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pace = (try? c.decode(Pace.self, forKey: .pace)) ?? .normal
        opponents = (try? c.decode(Opponents.self, forKey: .opponents)) ?? .ghosts
        reduceMotion = (try? c.decode(Bool.self, forKey: .reduceMotion)) ?? false
    }
}
