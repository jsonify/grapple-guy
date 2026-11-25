import SpriteKit
import GrappleCore

/// Line-art stickman drawn from the torso position (issue #8).
/// Milestone 2 replaces the procedural pose with hybrid ragdoll limbs.
final class StickmanNode: SKNode {
    private let shape = SKShapeNode()
    /// Smoothed "up" direction of the body so the pose doesn't snap.
    private var up = Vec2(0, 1)
    private(set) var handPosition = Vec2.zero

    override init() {
        super.init()
        shape.strokeColor = Palette.stickman
        shape.lineWidth = 5
        shape.lineCap = .round
        shape.lineJoin = .round
        shape.fillColor = .clear
        addChild(shape)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setCrashed(_ crashed: Bool) {
        shape.strokeColor = crashed ? Palette.crashed : Palette.stickman
    }

    func update(torso c: Vec2, velocity v: Vec2, ropeAnchor: Vec2?, dt: Double) {
        // Hang toward the anchor on a rope; otherwise stay mostly upright, leaning into motion.
        let targetUp: Vec2
        if let anchor = ropeAnchor {
            targetUp = (anchor - c).normalized
        } else {
            targetUp = Vec2(v.x * 0.0004, 1).normalized
        }
        let blend = 1 - exp(-12 * dt)
        up = (up + (targetUp - up) * blend).normalized
        if up == .zero { up = Vec2(0, 1) }
        let down = -up

        // The collider is a small circle at the torso; draw the figure raised so its feet,
        // not its waist, rest on the ground.
        let body = c + up * 18
        let shoulder = body + up * 13
        let hip = body - up * 13
        let headCenter = shoulder + up * 12
        let headRadius = 9.0

        // Legs trail slightly against the direction of travel.
        let trail = Vec2(-max(-1, min(1, v.x / 1500)) * 0.4, 0)
        let leftFoot = hip + (down.rotated(by: 0.35) + trail).normalized * 24
        let rightFoot = hip + (down.rotated(by: -0.35) + trail).normalized * 24

        let leadHand: Vec2
        let otherHand: Vec2
        if let anchor = ropeAnchor {
            leadHand = shoulder + (anchor - shoulder).normalized * 20
            otherHand = shoulder + down.rotated(by: v.x >= 0 ? -0.7 : 0.7) * 18
        } else {
            leadHand = shoulder + down.rotated(by: 1.9) * 18
            otherHand = shoulder + down.rotated(by: -1.9) * 18
        }
        handPosition = leadHand

        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: headCenter.x - headRadius, y: headCenter.y - headRadius,
                                   width: headRadius * 2, height: headRadius * 2))
        path.move(to: CGPoint(shoulder)); path.addLine(to: CGPoint(hip))
        path.move(to: CGPoint(hip)); path.addLine(to: CGPoint(leftFoot))
        path.move(to: CGPoint(hip)); path.addLine(to: CGPoint(rightFoot))
        path.move(to: CGPoint(shoulder)); path.addLine(to: CGPoint(leadHand))
        path.move(to: CGPoint(shoulder)); path.addLine(to: CGPoint(otherHand))
        shape.path = path
    }
}
