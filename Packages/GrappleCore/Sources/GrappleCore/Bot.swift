/// How good a bot is (issue #32). Skill comes from how many options it considers, how fast it reacts,
/// how precise its aim and timing are, and how often it picks a worse plan.
public struct BotSkill: Equatable, Sendable {
    public var name: String
    /// Seconds before acting (thinking time).
    public var reaction: Double
    /// How many reachable pads it considers per shot.
    public var candidatePads: Int
    /// Hold durations (seconds after the rope attaches) it considers.
    public var holdOptions: [Double]
    /// Random aim error, in points.
    public var aimNoise: Double
    /// Random hold-timing error, in seconds.
    public var timingNoise: Double
    /// Chance of picking the second- or third-best plan instead of the best.
    public var mistakeChance: Double

    public init(name: String, reaction: Double, candidatePads: Int, holdOptions: [Double],
                aimNoise: Double, timingNoise: Double, mistakeChance: Double) {
        self.name = name
        self.reaction = reaction
        self.candidatePads = candidatePads
        self.holdOptions = holdOptions
        self.aimNoise = aimNoise
        self.timingNoise = timingNoise
        self.mistakeChance = mistakeChance
    }

    public static let rookie = BotSkill(name: "Rookie Rita", reaction: 0.55, candidatePads: 2, holdOptions: [0.25, 0.6],
                                        aimNoise: 60, timingNoise: 0.2, mistakeChance: 0.35)
    public static let steady = BotSkill(name: "Steady Sam", reaction: 0.35, candidatePads: 4, holdOptions: [0.1, 0.35, 0.6, 0.9],
                                        aimNoise: 25, timingNoise: 0.1, mistakeChance: 0.15)
    public static let pro = BotSkill(name: "Pro Pip", reaction: 0.2, candidatePads: 6, holdOptions: [0, 0.2, 0.4, 0.6, 0.8, 1.1],
                                     aimNoise: 8, timingNoise: 0.04, mistakeChance: 0.05)
}

/// A computer opponent. It plays its own `SwingSimulation` through the same controls as the player
/// (fire, hold, let go) and plans each shot by simulating candidate plans ahead and picking the best.
public final class Bot {
    public let skill: BotSkill
    public private(set) var sim: SwingSimulation
    /// How far the bot's rope reaches (the scene sets this to match the player's screen-based range).
    public var ropeRange: Double

    private struct Plan {
        var target: Vec2
        var hold: Double
    }

    /// Plans scoring at or below this attach nowhere useful (missed, own pad, crash): don't spend a swing on them.
    static let hopeless = -9e5

    private enum Phase {
        case thinking(until: Double)
        case firing(Plan)
        case holding(releaseAt: Double)
        case flying(replanAt: Double)
        case crashed(respawnAt: Double)
        case done
    }

    private var phase: Phase
    private var clock: Double = 0
    /// Stuck detection: furthest x reached, and swings since it last improved.
    private var bestX = -Double.infinity
    private var swingsWithoutProgress = 0
    private var lastFaithShot = -Double.infinity
    /// Like golf's pick-up rule: a bot stops after this many swings and takes a DNF.
    public var swingLimit: Int
    public private(set) var gaveUp = false
    private var random: SeededRandom
    private let seed: UInt64
    private let wind: Double

    /// Step used when simulating plans ahead (coarser than the real step, for speed).
    static let planningStep = 1.0 / 60.0

    public init(level: Level, tuning: Tuning = .default, skill: BotSkill, seed: UInt64, wind: Double, ropeRange: Double) {
        self.skill = skill
        self.seed = seed
        self.wind = wind
        self.ropeRange = ropeRange
        swingLimit = max(8, level.par * 2 + 2)
        random = SeededRandom(seed: seed)
        sim = SwingSimulation(level: level, tuning: tuning, seed: seed, wind: wind)
        phase = .thinking(until: skill.reaction)
    }

    public var isFinished: Bool {
        if case .finished = sim.state { return true }
        return false
    }

    /// Finished, or gave up at the swing limit.
    public var hasStopped: Bool { isFinished || gaveUp }

    /// Starts the hole over (same wind and seed).
    public func reset() {
        sim = SwingSimulation(level: sim.level, tuning: sim.tuning, seed: seed, wind: wind)
        random = SeededRandom(seed: seed)
        clock = 0
        bestX = -.infinity
        swingsWithoutProgress = 0
        lastFaithShot = -.infinity
        gaveUp = false
        phase = .thinking(until: skill.reaction)
    }

    /// Decides what to do, then advances its simulation by `deltaTime`.
    @discardableResult
    public func update(deltaTime: Double) -> [SimEvent] {
        clock += deltaTime
        if gaveUp { return [] }
        decide()
        let events = sim.update(deltaTime: deltaTime)
        for event in events {
            if case .penalty = event { phase = .thinking(until: clock + skill.reaction) }
        }
        return events
    }

    /// Plays on at full speed until finished (or `maxSeconds` of game time), e.g. once the player finishes.
    public func finishInstantly(maxSeconds: Double = 90) {
        let step = 1.0 / 60.0
        var simulated = 0.0
        while !hasStopped && simulated < maxSeconds {
            update(deltaTime: step)
            simulated += step
        }
    }

    private func decide() {
        if isFinished {
            phase = .done
            return
        }
        if sim.strokes >= swingLimit && sim.rope == nil && sim.shot == nil {
            gaveUp = true
            phase = .done
            return
        }
        if sim.position.x > bestX + 150 {
            bestX = sim.position.x
            swingsWithoutProgress = 0
        }
        if sim.state == .crashed {
            if case .crashed(let at) = phase {
                if clock >= at {
                    sim.respawn()
                    phase = .thinking(until: clock + skill.reaction)
                }
            } else {
                phase = .crashed(respawnAt: clock + 1)
            }
            return
        }

        switch phase {
        case .thinking(let until):
            guard clock >= until else { return }
            guard let plan = makePlan() else {
                // Nothing useful in reach: wait (or fall) and look again, with an occasional shot of faith.
                if clock - lastFaithShot > 2 && sim.fireGrapple(toward: sim.position + Vec2(700, 650), range: ropeRange) {
                    lastFaithShot = clock
                    swingsWithoutProgress += 1
                    phase = .firing(Plan(target: sim.position + Vec2(700, 650), hold: 0.5))
                } else {
                    phase = .thinking(until: clock + 0.3)
                }
                return
            }
            if sim.fireGrapple(toward: plan.target, range: ropeRange) {
                swingsWithoutProgress += 1
                phase = .firing(plan)
            } else {
                phase = .thinking(until: clock + 0.2)
            }
        case .firing(let plan):
            if sim.rope != nil {
                let jitter = Double.random(in: -skill.timingNoise...skill.timingNoise, using: &random)
                phase = .holding(releaseAt: clock + max(0, plan.hold + jitter))
            } else if sim.shot == nil {
                phase = .thinking(until: clock + skill.reaction * 0.5)  // missed or clanked: rethink
            }
        case .holding(let releaseAt):
            if clock >= releaseAt || sim.rope == nil {
                sim.release()
                phase = .flying(replanAt: clock + max(0.15, skill.reaction * 0.8))
            }
        case .flying(let replanAt):
            if clock >= replanAt { phase = .thinking(until: clock) }
        case .crashed:
            phase = .thinking(until: clock + skill.reaction)
        case .done:
            break
        }
    }

    // MARK: - Planning

    /// The best plan, or nil if nothing in reach is worth a swing.
    private func makePlan() -> Plan? {
        let here = sim.position
        // When stuck, look at everything in reach with more hold options.
        let stuck = swingsWithoutProgress >= 3
        let holds = stuck ? [0, 0.3, 0.6, 0.9, 1.2, 1.6] : skill.holdOptions
        let pads = sim.level.surfaces
            .filter { $0.isGrappleable }
            .map(\.bounds)
            .filter { $0.center.x > here.x - 150 && $0.center.distance(to: here) <= ropeRange }
            .sorted { $0.center.x > $1.center.x }  // farthest ahead first
            .prefix(stuck ? 12 : max(1, skill.candidatePads))

        var scored: [(plan: Plan, score: Double)] = []
        for pad in pads {
            for hold in holds {
                // Aim at the pad's middle: the rope hits whichever face is visible (top or bottom).
                let plan = Plan(target: pad.center, hold: hold)
                let score = evaluate(plan, pad: pad)
                if score > Self.hopeless { scored.append((plan, score)) }
            }
        }
        guard !scored.isEmpty else { return nil }

        scored.sort { $0.score > $1.score }
        var pick = 0
        if scored.count > 1 && Double.random(in: 0..<1, using: &random) < skill.mistakeChance {
            pick = Int.random(in: 1...min(2, scored.count - 1), using: &random)
        }
        var chosen = scored[pick].plan
        chosen.target = chosen.target + Vec2(Double.random(in: -skill.aimNoise...skill.aimNoise, using: &random),
                                             Double.random(in: -skill.aimNoise...skill.aimNoise, using: &random))
        return chosen
    }

    /// Simulates a plan ahead (fire → hold → let go → fly) and scores where it ends up.
    private func evaluate(_ plan: Plan, pad: AABB) -> Double {
        let lookahead = sim.copy()
        lookahead.simulatesRagdoll = false
        let startPenalties = lookahead.penalties
        let dt = Self.planningStep
        guard lookahead.fireGrapple(toward: plan.target, range: ropeRange) else { return -.infinity }

        // Wait for the rope to attach (or fail).
        var t = 0.0
        while lookahead.rope == nil && lookahead.shot != nil && t < 1.0 {
            lookahead.step(dt)
            t += dt
        }
        // Must catch the intended pad, and not one right underneath (that just wastes a swing).
        guard let anchor = lookahead.rope?.anchor else { return -1e6 }
        let padZone = AABB(x: pad.lower.x - 2, y: pad.lower.y - 2, width: pad.width + 4, height: pad.height + 4)
        guard padZone.contains(anchor), anchor.distance(to: sim.position) > 120 else { return -1e6 }

        t = 0
        while t < plan.hold && lookahead.state == .playing && lookahead.penalties == startPenalties {
            lookahead.step(dt)
            t += dt
        }
        lookahead.release()
        t = 0
        while t < 1.4 && lookahead.state == .playing && lookahead.penalties == startPenalties {
            lookahead.step(dt)
            t += dt
        }
        return Self.score(lookahead, startPenalties: startPenalties)
    }

    static func score(_ s: SwingSimulation, startPenalties: Int) -> Double {
        switch s.state {
        case .finished(let time): return 1e6 - time * 100
        case .crashed: return -1e6
        case .playing: break
        }
        if s.penalties > startPenalties { return -5e5 }
        var score = s.position.x + 0.25 * s.velocity.x + 0.15 * min(s.position.y, 900)
        if s.position.y < s.level.killY + 250 { score -= 1e5 }
        return score
    }
}

/// One player's result on a hole.
public struct RaceEntry: Equatable, Sendable {
    public var name: String
    public var strokes: Int
    /// Finish time, or nil if they didn't finish.
    public var time: Double?
    public var isPlayer: Bool

    public init(name: String, strokes: Int, time: Double?, isPlayer: Bool = false) {
        self.name = name
        self.strokes = strokes
        self.time = time
        self.isPlayer = isPlayer
    }
}

public enum RaceStandings {
    /// Finishers first, then fewest strokes, then fastest time (#32).
    public static func rank(_ entries: [RaceEntry]) -> [RaceEntry] {
        entries.sorted { a, b in
            switch (a.time, b.time) {
            case (nil, .some): return false
            case (.some, nil): return true
            default: break
            }
            if a.strokes != b.strokes { return a.strokes < b.strokes }
            return (a.time ?? .infinity) < (b.time ?? .infinity)
        }
    }
}
