import SpriteKit
import GrappleCore

/// Draws the ragdoll's joints as a line-art stickman: thick, round-capped strokes.
final class StickmanNode: SKNode {
    private let shape = SKShapeNode()
    private let headRadius = 9.0

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

    func update(ragdoll r: Ragdoll) {
        let path = CGMutablePath()
        let head = r[.head]
        path.addEllipse(in: CGRect(x: head.x - headRadius, y: head.y - headRadius,
                                   width: headRadius * 2, height: headRadius * 2))

        func limb(_ joints: Ragdoll.Joint...) {
            path.move(to: CGPoint(r[joints[0]]))
            for joint in joints.dropFirst() { path.addLine(to: CGPoint(r[joint])) }
        }
        limb(.neck, .pelvis)
        limb(.neck, .leftElbow, .leftHand)
        limb(.neck, .rightElbow, .rightHand)
        limb(.pelvis, .leftKnee, .leftFoot)
        limb(.pelvis, .rightKnee, .rightFoot)
        shape.path = path
    }
}
