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
    private let ropeNode = SKShapeNode()
    private let statusLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let timerLabel = SKLabelNode(fontNamed: "Menlo")
    private let hintLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    /// Big "SWINGS 3 / PAR 5" counter, top centre.
    private let swingsLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    /// Level name and rules, shown at the start of each attempt.
    private let introLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    /// Points toward the goal flag while it's off screen.
    private let goalArrow = SKLabelNode(fontNamed: "Menlo-Bold")
    private var shownSwings = 0
    private var hasAttachedOnce = false
    private var gemNodes: [SKShapeNode] = []
    private var checkpointNodes: [SKShapeNode] = []
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
        background = ParallaxBackground(scene: self, level: simulation.level)

        buildLevel()

        ropeNode.strokeColor = Palette.rope
        ropeNode.lineWidth = 3
        ropeNode.lineCap = .round
        world.addChild(ropeNode)
        world.addChild(stickman)

        statusLabel.fontSize = 28
        statusLabel.fontColor = Palette.stickman
        statusLabel.verticalAlignmentMode = .center
        cameraNode.addChild(statusLabel)

        statusLabel.numberOfLines = 0
        timerLabel.fontSize = 20
        timerLabel.fontColor = Palette.stickman
        timerLabel.horizontalAlignmentMode = .left
        timerLabel.verticalAlignmentMode = .top
        cameraNode.addChild(timerLabel)

        hintLabel.fontSize = 22
        hintLabel.fontColor = Palette.stickman
        hintLabel.numberOfLines = 2
        hintLabel.horizontalAlignmentMode = .center
        hintLabel.verticalAlignmentMode = .center
        hintLabel.text = "Tap to shoot your rope at ORANGE blocks\nHold to pull in · let go to fly"
        hintLabel.run(.repeatForever(.sequence([.fadeAlpha(to: 0.45, duration: 0.8), .fadeAlpha(to: 1, duration: 0.8)])))
        cameraNode.addChild(hintLabel)

        swingsLabel.fontSize = 30
        swingsLabel.verticalAlignmentMode = .top
        cameraNode.addChild(swingsLabel)

        introLabel.fontSize = 30
        introLabel.numberOfLines = 0
        introLabel.verticalAlignmentMode = .center
        introLabel.fontColor = Palette.stickman
        cameraNode.addChild(introLabel)

        goalArrow.fontSize = 24
        goalArrow.fontColor = Palette.finish
        goalArrow.horizontalAlignmentMode = .right
        goalArrow.verticalAlignmentMode = .center
        cameraNode.addChild(goalArrow)

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
        // HUD children of the camera use screen points.
        timerLabel.position = CGPoint(x: -size.width / 2 + 24, y: size.height / 2 - 16)
        statusLabel.position = CGPoint(x: 0, y: size.height * 0.12)
        hintLabel.position = CGPoint(x: 0, y: -size.height * 0.32)
        swingsLabel.position = CGPoint(x: 0, y: size.height / 2 - 14)
        introLabel.position = CGPoint(x: 0, y: size.height * 0.12)
        goalArrow.position = CGPoint(x: size.width / 2 - 24, y: 0)
    }

    private func buildLevel() {
        for surface in simulation.level.surfaces {
            let b = surface.bounds
            let node = SKShapeNode(rect: CGRect(x: b.lower.x, y: b.lower.y, width: b.width, height: b.height), cornerRadius: 4)
            node.fillColor = surface.isGrappleable ? Palette.grappleable : Palette.solid
            node.strokeColor = .clear
            world.addChild(node)
        }

        // Goal: a tall flag standing on whatever surface is under the finish line.
        let finishX = simulation.level.finishX
        let groundY = simulation.level.surfaces
            .filter { $0.bounds.lower.x <= finishX && $0.bounds.upper.x >= finishX && $0.bounds.upper.y <= 100 }
            .map(\.bounds.upper.y).max() ?? 0
        let band = SKShapeNode(rect: CGRect(x: finishX - 3, y: simulation.level.killY, width: 6, height: 2000))
        band.fillColor = Palette.finish.withAlphaComponent(0.25)
        band.strokeColor = .clear
        world.addChild(band)
        let flagPath = CGMutablePath()
        flagPath.move(to: .zero)
        flagPath.addLine(to: CGPoint(x: 0, y: 260))
        let pole = SKShapeNode(path: flagPath)
        pole.strokeColor = Palette.stickman
        pole.lineWidth = 6
        pole.lineCap = .round
        pole.position = CGPoint(x: finishX, y: groundY)
        world.addChild(pole)
        let pennant = CGMutablePath()
        pennant.move(to: CGPoint(x: 0, y: 260))
        pennant.addLine(to: CGPoint(x: 110, y: 222))
        pennant.addLine(to: CGPoint(x: 0, y: 184))
        pennant.closeSubpath()
        let flag = SKShapeNode(path: pennant)
        flag.fillColor = Palette.finish
        flag.strokeColor = .clear
        flag.position = pole.position
        world.addChild(flag)
        let goalText = SKLabelNode(fontNamed: "Menlo-Bold")
        goalText.text = "GOAL"
        goalText.fontSize = 34
        goalText.fontColor = Palette.finish
        goalText.position = CGPoint(x: finishX, y: groundY + 290)
        world.addChild(goalText)

        for gem in simulation.level.gems {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 16))
            path.addLine(to: CGPoint(x: 12, y: 0))
            path.addLine(to: CGPoint(x: 0, y: -16))
            path.addLine(to: CGPoint(x: -12, y: 0))
            path.closeSubpath()
            let node = SKShapeNode(path: path)
            node.fillColor = Palette.gem
            node.strokeColor = Palette.gem.withAlphaComponent(0.5)
            node.lineWidth = 4
            node.position = CGPoint(gem)
            world.addChild(node)
            gemNodes.append(node)
        }

        for checkpoint in simulation.level.checkpoints {
            let path = CGMutablePath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0, y: 90))
            path.addLine(to: CGPoint(x: 36, y: 76))
            path.addLine(to: CGPoint(x: 0, y: 62))
            let node = SKShapeNode(path: path)
            node.strokeColor = Palette.solid
            node.lineWidth = 4
            node.lineCap = .round
            node.lineJoin = .round
            node.position = CGPoint(x: checkpoint.position.x, y: checkpoint.position.y - simulation.tuning.torsoRadius)
            world.addChild(node)
            checkpointNodes.append(node)
        }
    }

    private func resetLevelDecorations() {
        for node in gemNodes {
            node.removeAllActions()
            node.alpha = 1
            node.setScale(1)
        }
        for node in checkpointNodes { node.strokeColor = Palette.solid }
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
                feedback.play(.attach, on: self)
                feedback.haptic(.medium)
                if !hasAttachedOnce {
                    hasAttachedOnce = true
                    hintLabel.removeAllActions()
                    hintLabel.run(.fadeOut(withDuration: 0.3))
                }
            case .ropeBlocked(let wallPoint):
                feedback.play(.clank, on: self)
                feedback.haptic(.rigid)
                showFailedShot(to: wallPoint, blocked: true)
            case .ropeMissed(let end):
                showFailedShot(to: end, blocked: false)
            case .gemCollected(let index):
                feedback.play(.gem, on: self)
                feedback.haptic(.light)
                gemNodes[index].run(.group([.scale(to: 2.2, duration: 0.25), .fadeOut(withDuration: 0.25)]))
            case .checkpointReached(let index):
                feedback.play(.checkpoint, on: self)
                feedback.haptic(.success)
                checkpointNodes[index].strokeColor = Palette.finish
            case .crashed:
                activeTouch = nil
                shake = 1
                hitStop = tuning.hitStopSeconds
                feedback.play(.crash, on: self)
                feedback.haptic(.heavy)
                stickman.setCrashed(true)
                statusLabel.text = simulation.activeCheckpoint == nil
                    ? "CRASHED!\nTap to try again from the start (your swings still count)"
                    : "CRASHED!\nTap to try again from the checkpoint flag (your swings still count)"
            case .finished:
                activeTouch = nil
                hitStop = tuning.hitStopSeconds / 2
                feedback.play(.finish, on: self)
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
            ropeNode.path = path
            ropeNode.alpha = (simulation.shot != nil || simulation.isRopeTaut) ? 1 : 0.5
        } else {
            ropeNode.path = nil
        }

        timerLabel.text = String(format: "◆ %d/%d   %.1fs",
                                 simulation.collectedGems.count, simulation.level.gems.count, simulation.elapsed)
        let swings = simulation.strokes
        let par = simulation.level.par
        swingsLabel.text = "SWINGS \(swings) / PAR \(par)"
        swingsLabel.fontColor = swings <= par ? Palette.stickman : Palette.crashed
        if swings != shownSwings {
            shownSwings = swings
            if swings > 0 {
                swingsLabel.removeAction(forKey: "bump")
                swingsLabel.setScale(1.35)
                swingsLabel.run(.scale(to: 1, duration: 0.2), withKey: "bump")
            }
        }

        // Arrow toward the goal while it's off screen to the right.
        let visibleRight = Double(cameraNode.position.x) + Double(size.width * cameraNode.xScale) / 2
        let toGoal = simulation.level.finishX - simulation.position.x
        if simulation.level.finishX > visibleRight && simulation.state == .playing {
            goalArrow.text = String(format: "GOAL %dm ▶", Int(max(0, toGoal) / 100))
            goalArrow.isHidden = false
        } else {
            goalArrow.isHidden = true
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
            restartLevel()
            return
        }

        activeTouch = touch
        hideIntro()
        let point = touch.location(in: self)
        let target = Vec2(point)
        let direction = (target - simulation.position).normalized
        let range = screenEdgeDistance(from: simulation.position, along: direction).map { $0 * tuning.ropeRangeScreenFactor }
        if simulation.fireGrapple(toward: target, range: range) {
            feedback.play(.shoot, on: self)
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
            feedback.play(.boost, on: self)
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
        statusLabel.text = nil
        cameraNode.position = CGPoint(simulation.position + Vec2(0, cameraLift))
        if simulation.strokes == 0 { showIntro() }
    }

    private func showIntro() {
        let level = simulation.level
        introLabel.text = "\(level.name.isEmpty ? "Level" : level.name)\n"
            + "Reach the GOAL flag in \(level.par) swings or fewer\n"
            + "Every rope shot is a swing · grab ◆ gems on the way"
        introLabel.removeAllActions()
        introLabel.alpha = 1
        introLabel.run(.sequence([.wait(forDuration: 4), .fadeOut(withDuration: 0.5)]))
    }

    private func hideIntro() {
        guard introLabel.alpha > 0 else { return }
        introLabel.removeAllActions()
        introLabel.run(.fadeOut(withDuration: 0.2))
    }

    private func showFinish() {
        guard let result = simulation.runResult else { return }
        let record = ProgressStore.save(result, for: simulation.level.name)
        func star(_ s: Star) -> String { result.stars.contains(s) ? "★" : "☆" }
        var lines = [
            "\(result.golfTerm)  \(result.strokes) swings (par \(result.par))",
            "\(star(.finished)) Reached the goal",
            "\(star(.par)) \(result.par) swings or fewer",
            "\(star(.allGems)) All gems (\(result.gemsCollected)/\(result.gemsTotal))",
        ]
        if let best = record.bestStrokes {
            lines.append(String(format: "Best: %d swings · %.1fs", best, record.bestTime ?? result.time))
        }
        lines.append("Tap to play again")
        statusLabel.text = lines.joined(separator: "\n")
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
