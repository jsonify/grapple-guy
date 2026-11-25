import SpriteKit
import GrappleCore

/// Builds the cartoon-rooftop look for level elements: chunky shapes, thick outlines, lit top edges.
enum LevelArt {
    static let outlineWidth: CGFloat = 5

    private static func rect(_ b: AABB) -> CGRect {
        CGRect(x: b.lower.x, y: b.lower.y, width: b.width, height: b.height)
    }

    /// Solid surface: a rooftop ledge or wall with a lit top rim and a few dark windows on tall walls.
    static func rooftop(_ b: AABB) -> SKNode {
        let node = SKNode()
        let r = rect(b)
        let corner = min(12, r.height / 2, r.width / 2)

        let body = SKShapeNode(rect: r, cornerRadius: corner)
        body.fillColor = Palette.rooftop
        body.strokeColor = Palette.outline
        body.lineWidth = outlineWidth
        node.addChild(body)

        // Windows on tall walls (only near the top, where they can be seen).
        if r.height > 160 && r.width >= 50 {
            let windows = CGMutablePath()
            let columns = max(1, Int((r.width - 20) / 34))
            let spacing = (r.width - 20) / CGFloat(columns)
            for row in 0..<6 {
                let y = r.maxY - 46 - CGFloat(row) * 44
                if y < r.minY + 20 { break }
                for c in 0..<columns {
                    windows.addRoundedRect(in: CGRect(x: r.minX + 10 + CGFloat(c) * spacing + (spacing - 16) / 2,
                                                      y: y, width: 16, height: 22),
                                           cornerWidth: 3, cornerHeight: 3)
                }
            }
            let windowNode = SKShapeNode(path: windows)
            windowNode.fillColor = Palette.rooftopWindow
            windowNode.strokeColor = .clear
            node.addChild(windowNode)
        }

        // Lit top rim.
        let rimHeight = min(14, r.height * 0.4)
        let rim = SKShapeNode(rect: CGRect(x: r.minX + 4, y: r.maxY - rimHeight - 3, width: r.width - 8, height: rimHeight),
                              cornerRadius: min(6, rimHeight / 2))
        rim.fillColor = Palette.rooftopRim
        rim.strokeColor = .clear
        node.addChild(rim)
        return node
    }

    /// Grappleable surface: a glowing orange grip pad with bolts.
    static func gripPad(_ b: AABB) -> SKNode {
        let node = SKNode()
        let r = rect(b)

        let glow = SKShapeNode(rect: r.insetBy(dx: -12, dy: -12), cornerRadius: 22)
        glow.fillColor = Palette.gripGlow
        glow.strokeColor = .clear
        glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.9), .fadeAlpha(to: 1, duration: 0.9)])))
        node.addChild(glow)

        let body = SKShapeNode(rect: r, cornerRadius: min(14, r.height / 2))
        body.fillColor = Palette.grip
        body.strokeColor = Palette.outline
        body.lineWidth = outlineWidth
        node.addChild(body)

        let stripe = SKShapeNode(rect: CGRect(x: r.minX + 8, y: r.maxY - 12, width: r.width - 16, height: 6), cornerRadius: 3)
        stripe.fillColor = Palette.gripLight
        stripe.strokeColor = .clear
        node.addChild(stripe)

        for x in [r.minX + 14, r.maxX - 14] {
            let bolt = SKShapeNode(circleOfRadius: 4)
            bolt.fillColor = Palette.outline
            bolt.strokeColor = .clear
            bolt.position = CGPoint(x: x, y: r.midY - 3)
            node.addChild(bolt)
        }
        return node
    }

    /// Collectible gem: an outlined diamond with a highlight that bobs up and down.
    static func gem() -> SKNode {
        let node = SKNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 24))
        path.addLine(to: CGPoint(x: 17, y: 2))
        path.addLine(to: CGPoint(x: 0, y: -22))
        path.addLine(to: CGPoint(x: -17, y: 2))
        path.closeSubpath()
        let body = SKShapeNode(path: path)
        body.fillColor = Palette.gem
        body.strokeColor = Palette.outline
        body.lineWidth = 4
        body.lineJoin = .round
        node.addChild(body)

        let shine = CGMutablePath()
        shine.move(to: CGPoint(x: -4, y: 16))
        shine.addLine(to: CGPoint(x: -11, y: 4))
        shine.addLine(to: CGPoint(x: -5, y: 4))
        shine.closeSubpath()
        let highlight = SKShapeNode(path: shine)
        highlight.fillColor = .white
        highlight.strokeColor = .clear
        node.addChild(highlight)

        body.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 8, duration: 0.7),
            .moveBy(x: 0, y: -8, duration: 0.7),
        ])))
        highlight.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 8, duration: 0.7),
            .moveBy(x: 0, y: -8, duration: 0.7),
        ])))
        return node
    }

    /// Golf flag on the goal rooftop, with a cup and a GOAL label.
    static func goalFlag() -> SKNode {
        let node = SKNode()
        let cup = SKShapeNode(ellipseOf: CGSize(width: 46, height: 14))
        cup.fillColor = Palette.outline
        cup.strokeColor = .clear
        cup.position = CGPoint(x: 0, y: 2)
        node.addChild(cup)

        let pole = SKShapeNode(rect: CGRect(x: -4, y: 0, width: 8, height: 250), cornerRadius: 4)
        pole.fillColor = .white
        pole.strokeColor = Palette.outline
        pole.lineWidth = 4
        node.addChild(pole)

        let pennant = CGMutablePath()
        pennant.move(to: CGPoint(x: 4, y: 248))
        pennant.addQuadCurve(to: CGPoint(x: 116, y: 214), control: CGPoint(x: 64, y: 252))
        pennant.addQuadCurve(to: CGPoint(x: 4, y: 176), control: CGPoint(x: 60, y: 186))
        pennant.closeSubpath()
        let flag = SKShapeNode(path: pennant)
        flag.fillColor = Palette.flag
        flag.strokeColor = Palette.outline
        flag.lineWidth = 4
        flag.lineJoin = .round
        node.addChild(flag)
        flag.run(.repeatForever(.sequence([
            .scaleX(to: 0.92, duration: 0.5),
            .scaleX(to: 1, duration: 0.5),
        ])))

        let label = SKLabelNode()
        label.attributedText = Theme.text("GOAL", size: 44, color: .white, outline: Palette.outline)
        label.position = CGPoint(x: 10, y: 285)
        node.addChild(label)
        return node
    }

    /// Checkpoint: a small flag whose pennant turns green when reached.
    static func checkpointFlag() -> (node: SKNode, pennant: SKShapeNode) {
        let node = SKNode()
        let pole = SKShapeNode(rect: CGRect(x: -3, y: 0, width: 6, height: 110), cornerRadius: 3)
        pole.fillColor = .white
        pole.strokeColor = Palette.outline
        pole.lineWidth = 3
        node.addChild(pole)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 3, y: 108))
        path.addLine(to: CGPoint(x: 52, y: 92))
        path.addLine(to: CGPoint(x: 3, y: 76))
        path.closeSubpath()
        let pennant = SKShapeNode(path: path)
        pennant.fillColor = Palette.checkpoint
        pennant.strokeColor = Palette.outline
        pennant.lineWidth = 3
        pennant.lineJoin = .round
        node.addChild(pennant)
        return (node, pennant)
    }
}
