import SpriteKit
import GrappleCore

/// Distant hills and clouds that scroll slower than the course (issue #20).
/// Each layer has a depth: 0 = stuck to the camera, 1 = moves with the world.
final class ParallaxBackground {
    private struct Layer {
        let node: SKNode
        let depth: Double
    }

    private var layers: [Layer] = []

    init(scene: SKScene, level: Level) {
        let minX = level.spawn.x - 1500
        let maxX = level.finishX + 1500
        layers = [
            makeHills(depth: 0.15, base: 120, amplitude: 140, wavelength: 900, color: Palette.farHills,
                      seed: 1.3, minX: minX, maxX: maxX, z: -30, clouds: true),
            makeHills(depth: 0.4, base: -170, amplitude: 90, wavelength: 520, color: Palette.nearHills,
                      seed: 4.1, minX: minX, maxX: maxX, z: -20, clouds: false),
        ]
        for layer in layers { scene.addChild(layer.node) }
    }

    /// Call every frame after the camera moves.
    func update(cameraPosition: CGPoint) {
        for layer in layers {
            let k = CGFloat(1 - layer.depth)
            layer.node.position = CGPoint(x: cameraPosition.x * k, y: cameraPosition.y * k)
        }
    }

    private func makeHills(depth: Double, base: Double, amplitude: Double, wavelength: Double, color: SKColor,
                           seed: Double, minX: Double, maxX: Double, z: CGFloat, clouds: Bool) -> Layer {
        let node = SKNode()
        node.zPosition = z
        // Content only needs to cover the part of the layer the camera can see.
        let from = minX * depth - 3500
        let to = maxX * depth + 3500

        let path = CGMutablePath()
        path.move(to: CGPoint(x: from, y: -4000))
        var x = from
        while x <= to {
            let y = base
                + amplitude * sin(x / wavelength + seed)
                + amplitude * 0.45 * sin(x / (wavelength * 0.37) + seed * 2.7)
            path.addLine(to: CGPoint(x: x, y: y))
            x += 60
        }
        path.addLine(to: CGPoint(x: to, y: -4000))
        path.closeSubpath()
        let hills = SKShapeNode(path: path)
        hills.fillColor = color
        hills.strokeColor = .clear
        node.addChild(hills)

        if clouds {
            var cx = from
            var i = 0.0
            while cx <= to {
                let cloud = SKNode()
                for (dx, dy, r) in [(0.0, 0.0, 55.0), (55, 12, 42), (-50, 8, 38), (20, 30, 40)] {
                    let puff = SKShapeNode(circleOfRadius: r)
                    puff.fillColor = Palette.cloud
                    puff.strokeColor = .clear
                    puff.position = CGPoint(x: dx, y: dy)
                    cloud.addChild(puff)
                }
                cloud.position = CGPoint(x: cx, y: 620 + 160 * sin(i * 2.3))
                cloud.setScale(0.8 + 0.4 * abs(sin(i * 1.7)))
                node.addChild(cloud)
                cx += 650 + 250 * abs(sin(i * 3.1))
                i += 1
            }
        }
        return Layer(node: node, depth: depth)
    }
}
