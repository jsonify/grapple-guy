import SpriteKit
import GrappleCore

/// Draws the ragdoll as a cartoon stickman: white limbs over a thick dark outline, and a filled, outlined head.
final class StickmanNode: SKNode {
    private let outline = SKShapeNode()
    private let limbs = SKShapeNode()
    private let head = SKShapeNode(circleOfRadius: 11)

    override init() {
        super.init()
        outline.strokeColor = Palette.outline
        outline.lineWidth = 11
        outline.lineCap = .round
        outline.lineJoin = .round
        addChild(outline)
        limbs.strokeColor = Palette.stickman
        limbs.lineWidth = 5
        limbs.lineCap = .round
        limbs.lineJoin = .round
        addChild(limbs)
        head.fillColor = Palette.stickman
        head.strokeColor = Palette.outline
        head.lineWidth = 4
        addChild(head)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setCrashed(_ crashed: Bool) {
        let color = crashed ? Palette.crashed : Palette.stickman
        limbs.strokeColor = color
        head.fillColor = color
    }

    func update(ragdoll r: Ragdoll) {
        // Stroke-only path: open lines would fill as triangles.
        let path = CGMutablePath()
        func limb(_ joints: Ragdoll.Joint...) {
            path.move(to: CGPoint(r[joints[0]]))
            for joint in joints.dropFirst() { path.addLine(to: CGPoint(r[joint])) }
        }
        limb(.head, .neck, .pelvis)
        limb(.neck, .leftElbow, .leftHand)
        limb(.neck, .rightElbow, .rightHand)
        limb(.pelvis, .leftKnee, .leftFoot)
        limb(.pelvis, .rightKnee, .rightFoot)
        outline.path = path
        limbs.path = path
        head.position = CGPoint(r[.head])
    }
}
