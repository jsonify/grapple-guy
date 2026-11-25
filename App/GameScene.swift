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
    private var hasAttachedOnce = false

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
        hintLabel.text = "Touch & hold near an ORANGE block to swing\nLet go to fly · reach the GREEN line"
        hintLabel.run(.repeatForever(.sequence([.fadeAlpha(to: 0.45, duration: 0.8), .fadeAlpha(to: 1, duration: 0.8)])))
        cameraNode.addChild(hintLabel)

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
        cameraNode.setScale(visibleHeight / size.height)
        // HUD children of the camera use screen points.
        timerLabel.position = CGPoint(x: -size.width / 2 + 24, y: size.height / 2 - 16)
        statusLabel.position = CGPoint(x: 0, y: size.height * 0.15)
        hintLabel.position = CGPoint(x: 0, y: -size.height * 0.32)
    }

    private func buildLevel() {
        for surface in simulation.level.surfaces {
            let b = surface.bounds
            let node = SKShapeNode(rect: CGRect(x: b.lower.x, y: b.lower.y, width: b.width, height: b.height), cornerRadius: 4)
            node.fillColor = surface.isGrappleable ? Palette.grappleable : Palette.solid
            node.strokeColor = .clear
            world.addChild(node)
        }

        let finish = SKShapeNode(rect: CGRect(x: simulation.level.finishX - 4, y: simulation.level.killY, width: 8, height: 1600))
        finish.fillColor = Palette.finish.withAlphaComponent(0.5)
        finish.strokeColor = .clear
        world.addChild(finish)
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate.map { min(currentTime - $0, 1.0 / 20.0) } ?? 0
        lastUpdate = currentTime

        for event in simulation.update(deltaTime: dt) {
            switch event {
            case .crashed:
                activeTouch = nil
                stickman.setCrashed(true)
                statusLabel.text = "CRASHED · tap to retry"
            case .finished(let time):
                activeTouch = nil
                statusLabel.text = String(format: "FINISHED in %.2fs · tap to restart", time)
            }
        }
        render(dt: dt)
    }

    private func render(dt: Double) {
        let anchor = simulation.rope?.anchor
        stickman.update(ragdoll: simulation.ragdoll)

        if let anchor {
            let path = CGMutablePath()
            path.move(to: CGPoint(simulation.ragdoll.ropeHand))
            path.addLine(to: CGPoint(anchor))
            ropeNode.path = path
            ropeNode.alpha = simulation.isRopeTaut ? 1 : 0.5
        } else {
            ropeNode.path = nil
        }

        timerLabel.text = String(format: "%.2f", simulation.elapsed)

        // Camera follows with look-ahead in the direction of travel; after a crash it follows the tumbling body.
        let crashed = simulation.state == .crashed
        let focus = crashed ? simulation.ragdoll[.pelvis] : simulation.position
        let v = crashed ? Vec2.zero : simulation.velocity
        let lookAhead = Vec2(max(-450, min(450, v.x * 0.3)), max(-200, min(200, v.y * 0.15)))
        let target = CGPoint(focus + lookAhead + Vec2(0, cameraLift))
        let follow = CGFloat(dt > 0 ? 1 - exp(-5 * dt) : 1)
        cameraNode.position.x += (target.x - cameraNode.position.x) * follow
        cameraNode.position.y += (target.y - cameraNode.position.y) * follow
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }

        guard simulation.state == .playing else {
            restart()
            return
        }

        activeTouch = touch
        let point = touch.location(in: self)
        if simulation.fireGrapple(toward: Vec2(point)) == nil {
            showMissMarker(at: point)
        } else if !hasAttachedOnce {
            hasAttachedOnce = true
            hintLabel.removeAllActions()
            hintLabel.run(.fadeOut(withDuration: 0.3))
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

    private func restart() {
        simulation.reset()
        stickman.setCrashed(false)
        statusLabel.text = nil
        cameraNode.position = CGPoint(simulation.position + Vec2(0, cameraLift))
    }

    private func showMissMarker(at point: CGPoint) {
        let s: CGFloat = 14
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -s, y: -s)); path.addLine(to: CGPoint(x: s, y: s))
        path.move(to: CGPoint(x: -s, y: s)); path.addLine(to: CGPoint(x: s, y: -s))
        let marker = SKShapeNode(path: path)
        marker.strokeColor = Palette.miss
        marker.lineWidth = 4
        marker.lineCap = .round
        marker.position = point
        world.addChild(marker)
        marker.run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))
    }
}
