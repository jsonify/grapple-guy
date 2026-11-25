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
    private let statusCard = Card(padding: CGSize(width: 30, height: 18), cornerRadius: 26)
    /// How-to hint until the first successful grapple.
    private let hintCard = Card(padding: CGSize(width: 18, height: 8))
    private var shownSwings = 0
    private var hasAttachedOnce = false
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

    /// Called when the player taps after finishing; ContentView moves on to the next level.
    var onContinue: (() -> Void)?

    var tuning: Tuning {
        get { simulation.tuning }
        set { simulation.tuning = newValue }
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

        for card in [infoCard, goalCard, swingsCard, hintCard, introCard, statusCard] {
            cameraNode.addChild(card)
        }
        statusCard.set(nil, maxWidth: 0)
        hintCard.run(.repeatForever(.sequence([.fadeAlpha(to: 0.55, duration: 0.8), .fadeAlpha(to: 1, duration: 0.8)])))

        showIntro()

        layoutForSize()
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
        statusCard.position = CGPoint(x: 0, y: size.height * 0.05)
        introCard.position = CGPoint(x: 0, y: size.height * 0.08)
        hintCard.set(Theme.text("Tap to shoot your rope at the ORANGE pads · hold to pull in · let go to fly", size: 17),
                     maxWidth: size.width * 0.9)
        hintCard.position = CGPoint(x: 0, y: -size.height / 2 + 40)
    }

    private func buildLevel() {
        for surface in simulation.level.surfaces {
            world.addChild(surface.isGrappleable ? LevelArt.gripPad(surface.bounds) : LevelArt.rooftop(surface.bounds))
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

        // Hit-stop: freeze the simulation briefly; rendering (shake, camera) keeps going.
        var simDt = dt
        if hitStop > 0 {
            hitStop -= dt
            simDt = 0
        }

        for event in simulation.update(deltaTime: simDt) {
            switch event {
            case .ropeAttached:
                feedback.play(.attach)
                feedback.haptic(.medium)
                if !hasAttachedOnce {
                    hasAttachedOnce = true
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
                ]), maxWidth: size.width * 0.9)
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
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }

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
        resetLevelDecorations()
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
            Theme.text("\(level.name.isEmpty ? "Level" : level.name)\n", size: 38, color: .white, outline: Palette.outline),
            Theme.text("Reach the ", size: 20),
            Theme.text("GOAL", size: 20, color: Palette.finish),
            Theme.text(" in ", size: 20),
            Theme.text("\(level.par) swings", size: 20, color: Palette.gold),
            Theme.text(" or fewer\nEvery rope shot is a swing · grab ", size: 20),
            Theme.text("◆", size: 20, color: Palette.gem),
            Theme.text(" gems on the way", size: 20),
        ]
        if !feedback.missingSounds.isEmpty {
            parts.append(Theme.text("\n⚠️ Sound files missing: run xcodegen and rebuild", size: 16, color: Palette.overPar))
        }
        introCard.set(Theme.join(parts), maxWidth: size.width * 0.9)
        introCard.removeAllActions()
        introCard.alpha = 1
        introCard.run(.sequence([.wait(forDuration: 4), .fadeOut(withDuration: 0.5)]))
    }

    private func hideIntro() {
        guard introCard.alpha > 0 else { return }
        introCard.removeAllActions()
        introCard.run(.fadeOut(withDuration: 0.2))
    }

    private func showFinish() {
        guard let result = simulation.runResult else { return }
        let record = ProgressStore.save(result, for: simulation.level.name)
        let faded = Palette.hudText.withAlphaComponent(0.6)
        func starLine(_ star: Star, _ label: String) -> [NSAttributedString] {
            let earned = result.stars.contains(star)
            return [
                Theme.text(earned ? "★ " : "☆ ", size: 26, color: earned ? Palette.gold : faded),
                Theme.text(label + "\n", size: 18, color: earned ? Palette.hudText : faded),
            ]
        }
        var parts: [NSAttributedString] = [
            Theme.text("\(result.golfTerm)\n", size: 42, color: Palette.gold, outline: Palette.outline),
            Theme.text("\(result.strokes) swings  ·  par \(result.par)\n", size: 20),
        ]
        parts += starLine(.finished, "Reached the goal")
        parts += starLine(.par, "\(result.par) swings or fewer")
        parts += starLine(.allGems, "All gems (\(result.gemsCollected)/\(result.gemsTotal))")
        if let best = record.bestStrokes {
            parts.append(Theme.text(String(format: "Best: %d swings · %.1fs\n", best, record.bestTime ?? result.time),
                                    size: 15, color: faded))
        }
        parts.append(Theme.text(onContinue == nil ? "Tap to play again" : "Tap for the next hole ▶", size: 20, color: Palette.boost))
        statusCard.set(Theme.join(parts), maxWidth: size.width * 0.9)
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
