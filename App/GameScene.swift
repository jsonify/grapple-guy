import SpriteKit
import UIKit
import GrappleCore

/// Renders the simulation and turns touches into rope shots (issue #8).
/// All physics lives in `GrappleCore.SwingSimulation`; this class only draws and handles input.
final class GameScene: SKScene {
    private let simulation: SwingSimulation
    private let world = SKNode()
    private let cameraNode = SKCameraNode()
    private let stickman = StickmanNode()
    /// Rope: a dark outline under a white core.
    private let ropeOutline = SKShapeNode()
    private let ropeNode = SKShapeNode()
    // HUD cards (children of the camera, in screen points).
    /// Big "SWINGS 3 / PAR 5" counter, top centre.
    private let swingsCard = Card(padding: CGSize(width: 22, height: 8))
    /// Gems and time, top left.
    private let infoCard = Card(padding: CGSize(width: 14, height: 6), cornerRadius: 14)
    /// Points toward the goal flag while it's off screen.
    private let goalCard = Card(padding: CGSize(width: 14, height: 6), cornerRadius: 14)
    /// Level name and rules, shown at the start of each attempt.
    private let introCard = Card(padding: CGSize(width: 30, height: 18), cornerRadius: 26)
    /// Crash and finish messages.
    private let statusCard = Card(fill: Palette.hudPanel.withAlphaComponent(0.96), padding: CGSize(width: 30, height: 16),
                                  cornerRadius: 26)
    /// How-to hint until the first successful grapple.
    private let hintCard = Card(padding: CGSize(width: 18, height: 8))
    /// Wind direction and strength (only on windy holes).
    private let windCard = Card(padding: CGSize(width: 14, height: 6), cornerRadius: 14)
    /// Short "SPLASH! +1" style banners.
    private let penaltyCard = Card(fill: Palette.overPar, stroke: Palette.outline, padding: CGSize(width: 20, height: 8))
    /// Live standings, under the gems/time card.
    private let standingsCard = Card(padding: CGSize(width: 14, height: 6), cornerRadius: 14)
    /// Big "3", "2", "1", "GO!" in the middle of the screen before the race starts.
    private let countdownLabel = SKLabelNode()
    /// Running until GO: nobody moves and the clock doesn't start, so everyone leaves together.
    private var countdown: RaceCountdown?

    /// Computer opponents racing the same hole (#32), each with its own stickman and rope.
    private struct BotView {
        let bot: Bot
        let color: SKColor
        let stickman: StickmanNode
        let ropeOutline: SKShapeNode
        let rope: SKShapeNode
        let nameTag: SKLabelNode
    }
    private var bots: [BotView] = []
    private static let botRoster: [(BotSkill, SKColor)] = [(.rookie, Palette.botRita), (.steady, Palette.botSam), (.pro, Palette.botPip)]

    private var shownSwings = 0
    /// The how-to hint shows until the first grapple of the session, not on every hole.
    private static var hasAttachedOnce = false
    private var gemNodes: [SKNode] = []
    private var checkpointPennants: [SKShapeNode] = []
    /// 0…1 screen-shake strength, decays every frame.
    private var shake: Double = 0
    /// Remaining freeze-frame time; the simulation pauses while it's positive.
    private var hitStop: Double = 0
    /// Camera scale before speed zoom, and the smoothed zoom factor.
    private var baseCameraScale: CGFloat = 1
    private var zoom: Double = 1
    private let feedback = Feedback()
    private var background: ParallaxBackground?

    private var lastUpdate: TimeInterval?
    private var activeTouch: UITouch?
    private var isBuilt = false

    /// How many world points tall the view shows.
    private let visibleHeight: CGFloat = 1400
    /// The camera sits this far above the stickman so the grappleable ceiling stays in view.
    private let cameraLift: Double = 300

    /// Shown above the level name in the intro, e.g. "Rooftop Nine · Hole 3".
    var holeLabel: String?

    /// Called when the player taps after finishing; ContentView moves on to the next level.
    var onContinue: (() -> Void)?

    var tuning: Tuning {
        get { simulation.tuning }
        set {
            simulation.tuning = newValue
            for view in bots { view.bot.sim.tuning = newValue }
        }
    }

    /// How the bots are drawn (the player's Opponents setting, #36). Hidden bots still race and are scored.
    var opponents: PlayerSettings.Opponents = .ghosts {
        didSet { applyOpponentStyle() }
    }

    init(level: Level) {
        simulation = SwingSimulation(level: level)
        super.init(size: CGSize(width: 1920, height: 1080))
        scaleMode = .resizeFill
        backgroundColor = Palette.background
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Setup

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = false
        guard !isBuilt else { return }
        isBuilt = true

        addChild(world)
        addChild(cameraNode)
        camera = cameraNode
        cameraNode.zPosition = 100  // HUD above the course
        background = ParallaxBackground(scene: self, camera: cameraNode, level: simulation.level)

        buildLevel()

        ropeOutline.strokeColor = Palette.outline
        ropeOutline.lineWidth = 7
        ropeOutline.lineCap = .round
        world.addChild(ropeOutline)
        ropeNode.strokeColor = Palette.rope
        ropeNode.lineWidth = 3
        ropeNode.lineCap = .round
        world.addChild(ropeNode)
        world.addChild(stickman)

        for card in [infoCard, standingsCard, goalCard, swingsCard, windCard, hintCard, introCard, statusCard, penaltyCard] {
            cameraNode.addChild(card)
        }
        statusCard.set(nil, maxWidth: 0)
        penaltyCard.set(nil, maxWidth: 0)
        // Explicit layering (the view ignores sibling order): message cards above the HUD.
        for card in [infoCard, standingsCard, goalCard, swingsCard, windCard, hintCard] { card.zPosition = 10 }
        introCard.zPosition = 20
        if Self.hasAttachedOnce { hintCard.alpha = 0 }
        penaltyCard.zPosition = 30
        statusCard.zPosition = 40
        countdownLabel.zPosition = 35
        countdownLabel.alpha = 0
        cameraNode.addChild(countdownLabel)

        startCountdown()
        showIntro()

        layoutForSize()
        makeBots()
        cameraNode.position = CGPoint(simulation.position + Vec2(0, cameraLift))
        render(dt: 0)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutForSize()
    }

    private func layoutForSize() {
        guard size.height > 0 else { return }
        baseCameraScale = visibleHeight / size.height
        cameraNode.setScale(baseCameraScale * CGFloat(zoom))
        background?.layout(screenSize: size)
        // HUD children of the camera use screen points.
        swingsCard.position = CGPoint(x: 0, y: size.height / 2 - 36)
        windCard.position = CGPoint(x: 0, y: size.height / 2 - 92)
        penaltyCard.position = CGPoint(x: 0, y: size.height * 0.18)
        updateWindCard()
        statusCard.position = CGPoint(x: 0, y: size.height * 0.05)
        introCard.position = CGPoint(x: 0, y: size.height * 0.08)
        countdownLabel.position = CGPoint(x: 0, y: -size.height * 0.16)
        hintCard.set(Theme.text("Tap an ORANGE pad · hold to pull in · let go to fly", size: 15),
                     maxWidth: size.width * 0.7)
        hintCard.position = CGPoint(x: 0, y: -size.height / 2 + 40)
    }

    private func buildLevel() {
        for surface in simulation.level.surfaces {
            if surface.isGrappleable {
                world.addChild(LevelArt.gripPad(surface.bounds))
            } else if surface.material == .sand {
                world.addChild(LevelArt.sand(surface.bounds))
            } else {
                world.addChild(LevelArt.rooftop(surface.bounds))
            }
        }
        for pool in simulation.level.water {
            let node = LevelArt.water(pool)
            node.zPosition = 1
            world.addChild(node)
        }

        // Goal: a golf flag standing on whatever rooftop is under the finish line.
        let finishX = simulation.level.finishX
        let groundY = simulation.level.surfaces
            .filter { $0.bounds.lower.x <= finishX && $0.bounds.upper.x >= finishX && $0.bounds.upper.y <= 100 }
            .map(\.bounds.upper.y).max() ?? 0
        let flag = LevelArt.goalFlag()
        flag.position = CGPoint(x: finishX, y: groundY)
        world.addChild(flag)

        for gem in simulation.level.gems {
            let node = LevelArt.gem()
            node.position = CGPoint(gem)
            world.addChild(node)
            gemNodes.append(node)
        }

        for checkpoint in simulation.level.checkpoints {
            let (node, pennant) = LevelArt.checkpointFlag()
            node.position = CGPoint(x: checkpoint.position.x + 50, y: checkpoint.position.y - simulation.tuning.torsoRadius)
            world.addChild(node)
            checkpointPennants.append(pennant)
        }
    }

    private func resetLevelDecorations() {
        for node in gemNodes {
            node.removeAllActions()
            node.alpha = 1
            node.setScale(1)
        }
        for pennant in checkpointPennants { pennant.fillColor = Palette.checkpoint }
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate.map { min(currentTime - $0, 1.0 / 20.0) } ?? 0
        lastUpdate = currentTime

        // Start countdown: everyone is held on the tee until GO (real time, so game speed doesn't stretch it).
        if var current = countdown {
            for event in current.advance(dt) { showCountdown(event) }
            countdown = current.isRunning ? current : nil
            if countdown != nil {
                render(dt: dt)
                return
            }
        }

        // Hit-stop: freeze the simulation briefly; rendering (shake, camera) keeps going.
        // Game speed: the player and the bots share one scaled clock, so races stay fair.
        var simDt = dt * max(0.1, tuning.gameSpeed)
        if hitStop > 0 {
            hitStop -= dt
            simDt = 0
        }

        // Bots race live while you play (and while you're respawning); once you finish they're fast-forwarded.
        if simulation.runResult == nil {
            let reach = playerRopeReach()
            for view in bots {
                view.bot.ropeRange = reach
                view.bot.update(deltaTime: simDt)
            }
        }

        for event in simulation.update(deltaTime: simDt) {
            switch event {
            case .ropeAttached:
                feedback.play(.attach)
                feedback.haptic(.medium)
                if !Self.hasAttachedOnce {
                    Self.hasAttachedOnce = true
                    hintCard.removeAllActions()
                    hintCard.run(.fadeOut(withDuration: 0.3))
                }
            case .ropeBlocked(let wallPoint):
                feedback.play(.clank)
                feedback.haptic(.rigid)
                showFailedShot(to: wallPoint, blocked: true)
            case .ropeMissed(let end):
                showFailedShot(to: end, blocked: false)
            case .gemCollected(let index):
                feedback.play(.gem)
                feedback.haptic(.light)
                gemNodes[index].run(.group([.scale(to: 2.2, duration: 0.25), .fadeOut(withDuration: 0.25)]))
            case .penalty(let reason, let at):
                activeTouch = nil
                showPenalty(reason, at: at)
            case .checkpointReached(let index):
                feedback.play(.checkpoint)
                feedback.haptic(.success)
                checkpointPennants[index].fillColor = Palette.finish
            case .crashed:
                activeTouch = nil
                shake = 1
                hitStop = tuning.hitStopSeconds
                feedback.play(.crash)
                feedback.haptic(.heavy)
                stickman.setCrashed(true)
                let from = simulation.activeCheckpoint == nil ? "the start" : "the checkpoint"
                statusCard.set(Theme.join([
                    Theme.text("OUCH!\n", size: 40, color: Palette.overPar, outline: Palette.outline),
                    Theme.text("Tap to go again from \(from)\nYour swings still count", size: 20),
                ]), maxWidth: size.width * 0.9, maxHeight: size.height * 0.8)
            case .finished:
                activeTouch = nil
                hitStop = tuning.hitStopSeconds / 2
                feedback.play(.finish)
                feedback.haptic(.success)
                showFinish()
            }
        }
        render(dt: dt)
    }

    private func render(dt: Double) {
        let anchor = simulation.rope?.anchor ?? simulation.shot?.tip
        stickman.update(ragdoll: simulation.ragdoll)

        if let anchor {
            let path = CGMutablePath()
            path.move(to: CGPoint(simulation.ragdoll.ropeHand))
            path.addLine(to: CGPoint(anchor))
            ropeOutline.path = path
            ropeNode.path = path
            let alpha: CGFloat = (simulation.shot != nil || simulation.isRopeTaut) ? 1 : 0.55
            ropeNode.alpha = alpha
            ropeOutline.alpha = alpha
        } else {
            ropeOutline.path = nil
            ropeNode.path = nil
        }

        let swings = simulation.strokes
        let par = simulation.level.par
        let dim = Palette.hudText.withAlphaComponent(0.8)
        swingsCard.set(Theme.join([
            Theme.text("SWINGS ", size: 18, color: dim),
            Theme.text("\(swings)", size: 30, color: swings <= par ? Palette.gold : Palette.overPar),
            Theme.text("  /  PAR \(par)", size: 18, color: dim),
        ]), maxWidth: size.width * 0.5)
        if swings != shownSwings {
            shownSwings = swings
            if swings > 0 { swingsCard.bump() }
        }

        infoCard.set(Theme.text(String(format: "◆ %d/%d    %.1fs", simulation.collectedGems.count,
                                       simulation.level.gems.count, simulation.elapsed), size: 18),
                     maxWidth: size.width * 0.3)
        infoCard.position = CGPoint(x: -size.width / 2 + 24 + infoCard.size.width / 2, y: size.height / 2 - 36)
        renderBots()

        // Arrow toward the goal while it's off screen to the right.
        let visibleRight = Double(cameraNode.position.x) + Double(size.width * cameraNode.xScale) / 2
        let toGoal = simulation.level.finishX - simulation.position.x
        if simulation.level.finishX > visibleRight && simulation.state == .playing {
            goalCard.set(Theme.text(String(format: "GOAL  %dm  ▶", Int(max(0, toGoal) / 100)), size: 18, color: Palette.finish),
                         maxWidth: size.width * 0.3)
            goalCard.position = CGPoint(x: size.width / 2 - 24 - goalCard.size.width / 2, y: 0)
        } else {
            goalCard.set(nil, maxWidth: 0)
        }

        // Shake the world, not the camera, so the HUD stays still.
        if shake > 0.01 {
            let amount = tuning.screenShake * shake
            world.position = CGPoint(x: Double.random(in: -amount...amount), y: Double.random(in: -amount...amount))
            shake *= exp(-7 * dt)
        } else if world.position != .zero {
            shake = 0
            world.position = .zero
        }

        // Camera follows with look-ahead in the direction of travel; after a crash it follows the tumbling body.
        let crashed = simulation.state == .crashed
        let focus = crashed ? simulation.ragdoll[.pelvis] : simulation.position
        let v = crashed ? Vec2.zero : simulation.velocity
        let lookAhead = Vec2(max(-450, min(450, v.x * 0.3)), max(-200, min(200, v.y * 0.15)))
        let target = CGPoint(focus + lookAhead + Vec2(0, cameraLift))
        let follow = CGFloat(dt > 0 ? 1 - exp(-5 * dt) : 1)
        cameraNode.position.x += (target.x - cameraNode.position.x) * follow
        cameraNode.position.y += (target.y - cameraNode.position.y) * follow

        // Zoom out with speed so fast swings feel fast and show more of what's ahead.
        let speedFraction = crashed ? 0 : min(1, simulation.velocity.length / max(1, tuning.speedZoomFullSpeed))
        let targetZoom = 1 + tuning.speedZoom * speedFraction
        zoom += (targetZoom - zoom) * (dt > 0 ? 1 - exp(-2.5 * dt) : 1)
        cameraNode.setScale(baseCameraScale * CGFloat(zoom))

        background?.update(cameraPosition: cameraNode.position)
        updateWindCard()
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        guard countdown == nil else { return }  // no jumping the start

        switch simulation.state {
        case .playing: break
        case .crashed:
            respawnAfterCrash()
            return
        case .finished:
            if let onContinue { onContinue() } else { restartLevel() }
            return
        }

        activeTouch = touch
        hideIntro()
        let point = touch.location(in: self)
        let target = Vec2(point)
        let direction = (target - simulation.position).normalized
        let range = screenEdgeDistance(from: simulation.position, along: direction).map { $0 * tuning.ropeRangeScreenFactor }
        if simulation.fireGrapple(toward: target, range: range) {
            feedback.play(.shoot)
            feedback.haptic(.light)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouch(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouch(touches)
    }

    private func endTouch(_ touches: Set<UITouch>) {
        guard let active = activeTouch, touches.contains(active) else { return }
        activeTouch = nil
        if simulation.release() {
            feedback.play(.boost)
            feedback.haptic(.medium)
            showBoostEffect()
        }
    }

    private func showBoostEffect() {
        let ring = SKShapeNode(circleOfRadius: 24)
        ring.strokeColor = Palette.boost
        ring.lineWidth = 5
        ring.position = CGPoint(simulation.position)
        world.addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 4, duration: 0.35), .fadeOut(withDuration: 0.35)]),
            .removeFromParent(),
        ]))
    }

    /// For the Tune panel: plays a sound and reports what the audio system says.
    func soundCheck() -> String {
        feedback.soundCheck()
    }

    /// Restarts the whole level (the ↺ button, or tapping after finishing).
    func restartLevel() {
        activeTouch = nil
        simulation.reset()
        for view in bots { view.bot.reset() }
        resetLevelDecorations()
        startCountdown()
        afterRespawn()
    }

    private func respawnAfterCrash() {
        simulation.respawn()
        afterRespawn()
    }

    private func afterRespawn() {
        stickman.setCrashed(false)
        statusCard.set(nil, maxWidth: 0)
        cameraNode.position = CGPoint(simulation.position + Vec2(0, cameraLift))
        if simulation.strokes == 0 { showIntro() }
    }

    private func showIntro() {
        let level = simulation.level
        var parts: [NSAttributedString] = [
            Theme.text(holeLabel.map { "\($0.uppercased())\n" } ?? "", size: 15, color: Palette.hudText.withAlphaComponent(0.7)),
            Theme.text("\(level.name.isEmpty ? "Level" : level.name)\n", size: 34, color: .white, outline: Palette.outline),
            Theme.text("Par \(level.par)", size: 20, color: Palette.gold),
            Theme.text(level.gems.isEmpty ? "" : "  ·  \(level.gems.count) ◆", size: 20, color: Palette.gem),
        ]
        if !feedback.missingSounds.isEmpty {
            parts.append(Theme.text("\n⚠️ Sound files missing: run xcodegen and rebuild", size: 16, color: Palette.overPar))
        }
        introCard.set(Theme.join(parts), maxWidth: size.width * 0.9, maxHeight: size.height * 0.7)
        introCard.removeAllActions()
        introCard.alpha = 1
        // During the start countdown the intro stays up until GO.
        if countdown == nil {
            introCard.run(.sequence([.wait(forDuration: 2.5), .fadeOut(withDuration: 0.5)]))
        }
    }

    /// Begins "3, 2, 1, GO!" (skipped when the Tune panel sets the beat to 0).
    private func startCountdown() {
        let next = RaceCountdown(beats: 3, beatSeconds: tuning.countdownBeatSeconds)
        countdown = next.duration > 0 ? next : nil
        countdownLabel.removeAllActions()
        countdownLabel.alpha = 0
    }

    private func showCountdown(_ event: RaceCountdown.Event) {
        let text: String
        let color: SKColor
        switch event {
        case .beat(let n):
            text = "\(n)"
            color = .white
            feedback.play(.countdown)
            feedback.haptic(.light)
        case .go:
            text = "GO!"
            color = Palette.gold
            feedback.play(.go)
            feedback.haptic(.medium)
            hideIntro()
        }
        countdownLabel.attributedText = Theme.text(text, size: 110, color: color, outline: Palette.outline)
        countdownLabel.removeAllActions()
        countdownLabel.alpha = 1
        countdownLabel.setScale(1.6)
        let pop = SKAction.scale(to: 1, duration: 0.18)
        pop.timingMode = .easeOut
        if event == .go {
            countdownLabel.run(.sequence([pop, .wait(forDuration: 0.35),
                                          .group([.fadeOut(withDuration: 0.3), .scale(to: 1.3, duration: 0.3)])]))
        } else {
            countdownLabel.run(pop)
        }
    }

    private func hideIntro() {
        guard introCard.alpha > 0 else { return }
        introCard.removeAllActions()
        introCard.run(.fadeOut(withDuration: 0.2))
    }

    private func showPenalty(_ reason: PenaltyReason, at point: Vec2) {
        let title: String
        switch reason {
        case .water:
            title = "SPLASH!  +1 swing"
            feedback.play(.splash)
            showSplash(at: point)
        case .outOfBounds:
            title = "OUT OF BOUNDS  +1 swing"
            feedback.play(.crash)
        }
        feedback.haptic(.heavy)
        shake = 0.6
        penaltyCard.set(Theme.text(title, size: 24, color: .white, outline: Palette.outline), maxWidth: size.width * 0.8)
        penaltyCard.removeAllActions()
        penaltyCard.alpha = 1
        penaltyCard.run(.sequence([.wait(forDuration: 1.4), .fadeOut(withDuration: 0.3)]))
        cameraNode.position = CGPoint(simulation.position + Vec2(0, cameraLift))
    }

    private func showSplash(at point: Vec2) {
        for i in 0..<10 {
            let drop = SKShapeNode(circleOfRadius: CGFloat.random(in: 6...12))
            drop.fillColor = Palette.waterLight
            drop.strokeColor = Palette.outline
            drop.lineWidth = 2
            drop.position = CGPoint(point)
            drop.zPosition = 2
            world.addChild(drop)
            let angle = Double.pi * (0.15 + 0.7 * Double(i) / 9)
            let distance = Double.random(in: 70...150)
            drop.run(.sequence([
                .group([
                    .move(by: CGVector(dx: cos(angle) * distance, dy: sin(angle) * distance), duration: 0.45),
                    .fadeOut(withDuration: 0.45),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    // MARK: - Bots

    private func makeBots() {
        let reach = playerRopeReach()
        for (index, entry) in Self.botRoster.enumerated() {
            let (skill, color) = entry
            let bot = Bot(level: simulation.level, tuning: tuning, skill: skill,
                          seed: UInt64(index + 1) &* 7919, wind: simulation.wind, ropeRange: reach)
            let stickman = StickmanNode(color: color)
            stickman.zPosition = -1
            world.addChild(stickman)
            let outline = SKShapeNode()
            outline.lineCap = .round
            outline.zPosition = -1.1
            world.addChild(outline)
            let rope = SKShapeNode()
            rope.lineCap = .round
            rope.zPosition = -1.05
            world.addChild(rope)
            let tag = SKLabelNode()
            tag.attributedText = Theme.text(skill.name.components(separatedBy: " ").last ?? skill.name,
                                            size: 16, color: color)
            tag.zPosition = -0.9
            world.addChild(tag)
            bots.append(BotView(bot: bot, color: color, stickman: stickman, ropeOutline: outline, rope: rope, nameTag: tag))
        }
        applyOpponentStyle()
    }

    /// Show: solid, outlined bots. Ghosts: see-through tints with thin ropes. Hide: not drawn, no live standings.
    private func applyOpponentStyle() {
        for view in bots {
            let hidden = opponents == .hide
            let ghost = opponents == .ghosts
            for node in [view.stickman, view.ropeOutline, view.rope, view.nameTag] as [SKNode] { node.isHidden = hidden }
            view.stickman.alpha = ghost ? Palette.botAlpha : 1
            view.ropeOutline.strokeColor = ghost ? .clear : Palette.outline
            view.ropeOutline.lineWidth = ghost ? 0 : 6
            view.rope.strokeColor = ghost ? view.color.withAlphaComponent(Palette.botAlpha) : view.color
            view.rope.lineWidth = ghost ? 2 : 2.5
            view.nameTag.alpha = ghost ? 0.7 : 1
        }
    }

    private func renderBots() {
        for view in bots {
            let sim = view.bot.sim
            view.stickman.update(ragdoll: sim.ragdoll)
            view.stickman.setCrashed(sim.state == .crashed)
            view.nameTag.position = CGPoint(sim.ragdoll[.head] + Vec2(0, 26))
            if let anchor = sim.rope?.anchor ?? sim.shot?.tip {
                let path = CGMutablePath()
                path.move(to: CGPoint(sim.ragdoll.ropeHand))
                path.addLine(to: CGPoint(anchor))
                view.ropeOutline.path = path
                view.rope.path = path
            } else {
                view.ropeOutline.path = nil
                view.rope.path = nil
            }
        }
        // Live standings: everyone's swings so far, in race order (not shown while opponents are hidden).
        guard opponents != .hide else {
            standingsCard.set(nil, maxWidth: 0)
            return
        }
        let lines = currentStandings().map { entry -> NSAttributedString in
            let name = entry.isPlayer ? "You" : (entry.name.components(separatedBy: " ").last ?? entry.name)
            let flag = entry.time == nil ? "" : " ⚑"
            return Theme.text("\(name) \(entry.strokes)\(flag)   ", size: 15,
                              color: entry.isPlayer ? Palette.gold : nameColor(entry.name))
        }
        standingsCard.set(Theme.join(lines), maxWidth: size.width * 0.34)
        standingsCard.position = CGPoint(x: -size.width / 2 + 24 + standingsCard.size.width / 2,
                                         y: size.height / 2 - 36 - infoCard.size.height / 2 - 8 - standingsCard.size.height / 2)
    }

    /// Everyone on the hole, ranked: finishers first, then fewest swings, then time.
    private func currentStandings() -> [RaceEntry] {
        var entries = bots.map { view -> RaceEntry in
            var time: Double?
            if case .finished(let t) = view.bot.sim.state { time = t }
            return RaceEntry(name: view.bot.skill.name, strokes: view.bot.sim.strokes, time: time)
        }
        var playerTime: Double?
        if case .finished(let t) = simulation.state { playerTime = t }
        entries.append(RaceEntry(name: "You", strokes: simulation.strokes, time: playerTime, isPlayer: true))
        return RaceStandings.rank(entries)
    }

    private func nameColor(_ name: String) -> SKColor {
        bots.first { $0.bot.skill.name == name }?.color ?? Palette.hudText
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }

    /// The player's rope reach at normal zoom (screen edge × factor), so bots get the same range.
    private func playerRopeReach() -> Double {
        let halfWidth = Double(size.width * baseCameraScale) / 2
        return max(tuning.ropeRange, halfWidth * tuning.ropeRangeScreenFactor)
    }

    private func updateWindCard() {
        let wind = simulation.wind * tuning.windStrength
        // Hide wind too weak to show as at least 1.
        guard abs(wind) >= 20 else {
            windCard.set(nil, maxWidth: 0)
            return
        }
        // Show strength as 1–5 arrows plus a number.
        let arrows = max(1, min(5, Int((abs(wind) / 80).rounded(.up))))
        let arrow = wind > 0 ? "▶" : "◀"
        let row = String(repeating: arrow, count: arrows)
        let text = wind > 0 ? "WIND  \(Int(abs(wind) / 20))  \(row)" : "\(row)  \(Int(abs(wind) / 20))  WIND"
        windCard.set(Theme.text(text, size: 16, color: Palette.boost), maxWidth: size.width * 0.4)
    }

    private func showFinish() {
        guard let result = simulation.runResult else { return }
        let record = ProgressStore.save(result, for: simulation.level.name)
        // Bots still on the course play on instantly so the hole can be scored now.
        for view in bots where !view.bot.hasStopped { view.bot.finishInstantly() }
        let standings = currentStandings()
        let place = (standings.firstIndex { $0.isPlayer } ?? 0) + 1
        let placeTitle = place == 1 ? "YOU WIN THE HOLE!" : "\(ordinal(place)) PLACE"
        var parts: [NSAttributedString] = [
            Theme.text("\(placeTitle)\n", size: 34, color: place == 1 ? Palette.gold : .white, outline: Palette.outline),
            Theme.text("\(result.golfTerm) · \(result.strokes) swings · par \(result.par)\n", size: 18),
        ]
        for (i, entry) in standings.enumerated() {
            let time = entry.time.map { String(format: "%.1fs", $0) } ?? "gave up"
            let line = "\(ordinal(i + 1))  \(entry.isPlayer ? "You" : entry.name)   \(entry.strokes) swings · \(time)\n"
            parts.append(Theme.text(line, size: 15, color: entry.isPlayer ? Palette.gold : nameColor(entry.name)))
        }
        // Stars on one line.
        let faded = Palette.hudText.withAlphaComponent(0.45)
        for (star, label) in [(Star.finished, "Goal"), (.par, "Par"), (.allGems, "Gems \(result.gemsCollected)/\(result.gemsTotal)")] {
            let earned = result.stars.contains(star)
            parts.append(Theme.text(earned ? "★ " : "☆ ", size: 20, color: earned ? Palette.gold : faded))
            parts.append(Theme.text(label + "     ", size: 15, color: earned ? Palette.hudText : faded))
        }
        var footer = "\n"
        if let best = record.bestStrokes {
            footer += String(format: "Best %d swings · %.1fs     ", best, record.bestTime ?? result.time)
        }
        parts.append(Theme.text(footer, size: 13, color: faded))
        parts.append(Theme.text(onContinue == nil ? "Tap to play again" : "Tap for the next hole ▶", size: 18, color: Palette.boost))
        statusCard.set(Theme.join(parts), maxWidth: size.width * 0.9, maxHeight: size.height * 0.86)
    }

    /// Distance from `p` to the edge of the visible world along `direction`, or nil if `p` is off screen.
    private func screenEdgeDistance(from p: Vec2, along direction: Vec2) -> Double? {
        let half = Vec2(Double(size.width * cameraNode.xScale) / 2, Double(size.height * cameraNode.yScale) / 2)
        let center = Vec2(cameraNode.position)
        var t = Double.infinity
        if direction.x > 1e-9 { t = min(t, (center.x + half.x - p.x) / direction.x) }
        if direction.x < -1e-9 { t = min(t, (center.x - half.x - p.x) / direction.x) }
        if direction.y > 1e-9 { t = min(t, (center.y + half.y - p.y) / direction.y) }
        if direction.y < -1e-9 { t = min(t, (center.y - half.y - p.y) / direction.y) }
        return t.isFinite && t > 0 ? t : nil
    }

    /// The rope clanking off a wall (blocked) or snapping back from the end of its range (missed),
    /// so the player can see why the shot failed.
    private func showFailedShot(to end: Vec2, blocked: Bool) {
        let path = CGMutablePath()
        path.move(to: CGPoint(simulation.ragdoll.ropeHand))
        path.addLine(to: CGPoint(end))
        let line = SKShapeNode(path: path)
        line.strokeColor = Palette.rope
        line.lineWidth = 3
        line.glowWidth = 0
        line.lineCap = .round
        line.alpha = blocked ? 0.9 : 0.35
        world.addChild(line)
        line.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))

        guard blocked else { return }
        let sparkPath = CGMutablePath()
        for i in 0..<8 {
            let direction = Vec2(1, 0).rotated(by: Double(i) * .pi / 4)
            sparkPath.move(to: CGPoint(direction * 6))
            sparkPath.addLine(to: CGPoint(direction * 16))
        }
        let spark = SKShapeNode(path: sparkPath)
        spark.strokeColor = Palette.miss
        spark.lineWidth = 3
        spark.lineCap = .round
        spark.position = CGPoint(end)
        world.addChild(spark)
        spark.run(.sequence([
            .group([.scale(to: 1.6, duration: 0.25), .fadeOut(withDuration: 0.25)]),
            .removeFromParent(),
        ]))
    }
}
