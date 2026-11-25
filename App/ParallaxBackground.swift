import SpriteKit
import UIKit
import GrappleCore

/// Sunset sky, sun, clouds and a two-layer city skyline that scroll slower than the course (issue #20).
/// Each layer has a depth: 0 = stuck to the camera, 1 = moves with the world.
final class ParallaxBackground {
    private struct Layer {
        let node: SKNode
        let depth: Double
    }

    private var layers: [Layer] = []
    private let sky = SKSpriteNode()
    private let sun = SKNode()

    init(scene: SKScene, camera: SKCameraNode, level: Level) {
        // Sky and sun are attached to the camera (they never scroll).
        sky.texture = Self.gradientTexture()
        sky.zPosition = -1000
        camera.addChild(sky)
        let glow = SKShapeNode(circleOfRadius: 120)
        glow.fillColor = Palette.sun.withAlphaComponent(0.35)
        glow.strokeColor = .clear
        sun.addChild(glow)
        let disc = SKShapeNode(circleOfRadius: 78)
        disc.fillColor = Palette.sun
        disc.strokeColor = .clear
        sun.addChild(disc)
        sun.zPosition = -990
        camera.addChild(sun)

        let minX = level.spawn.x - 1500
        let maxX = level.finishX + 1500
        layers = [
            makeSkyline(depth: 0.15, baseY: -2000, heights: 150...650, widths: 140...280, color: Palette.farCity,
                        windows: Palette.farWindows, minX: minX, maxX: maxX, z: -30, seed: 3, clouds: true),
            makeSkyline(depth: 0.4, baseY: -3000, heights: -380...80, widths: 180...340, color: Palette.nearCity,
                        windows: Palette.nearWindows, minX: minX, maxX: maxX, z: -20, seed: 11, clouds: false),
        ]
        for layer in layers { scene.addChild(layer.node) }
    }

    /// Call when the screen size changes (camera children use screen points).
    func layout(screenSize: CGSize) {
        sky.size = CGSize(width: screenSize.width + 4, height: screenSize.height + 4)
        sun.position = CGPoint(x: screenSize.width * 0.22, y: -screenSize.height * 0.02)
    }

    /// Call every frame after the camera moves.
    func update(cameraPosition: CGPoint) {
        for layer in layers {
            let k = CGFloat(1 - layer.depth)
            layer.node.position = CGPoint(x: cameraPosition.x * k, y: cameraPosition.y * k)
        }
    }

    private static func gradientTexture() -> SKTexture {
        let size = CGSize(width: 4, height: 256)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [Palette.skyTop.cgColor, Palette.skyMid.cgColor, Palette.skyBottom.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                            locations: [0, 0.62, 1]) else { return }
            // UIKit draws top-down: top of the image is the top of the sky.
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        return SKTexture(image: image)
    }

    private func makeSkyline(depth: Double, baseY: Double, heights: ClosedRange<Double>, widths: ClosedRange<Double>,
                             color: SKColor, windows: SKColor, minX: Double, maxX: Double, z: CGFloat,
                             seed: UInt64, clouds: Bool) -> Layer {
        let node = SKNode()
        node.zPosition = z
        var random = SceneryRandom(seed: seed)
        // Content only needs to cover the part of the layer the camera can see.
        let from = minX * depth - 3500
        let to = maxX * depth + 3500

        if clouds {
            var cx = from
            while cx <= to {
                let cloud = SKNode()
                for _ in 0..<4 {
                    let puff = SKShapeNode(circleOfRadius: random.next(34...60))
                    puff.fillColor = Palette.cloud
                    puff.strokeColor = .clear
                    puff.position = CGPoint(x: random.next(-70...70), y: random.next(-12...18))
                    cloud.addChild(puff)
                }
                cloud.position = CGPoint(x: cx, y: random.next(820...1050))
                node.addChild(cloud)
                cx += random.next(600...1000)
            }
        }

        let buildings = CGMutablePath()
        let lights = CGMutablePath()
        var x = from
        while x <= to {
            let width = random.next(widths)
            let top = random.next(heights)
            buildings.addRect(CGRect(x: x, y: baseY, width: width - 6, height: top - baseY))
            // Rooftop details: some buildings get an antenna or a water tower.
            let detail = random.next()
            if detail < 0.25 {
                buildings.addRect(CGRect(x: x + width * 0.45, y: top, width: 6, height: random.next(40...90)))
            } else if detail < 0.4 {
                buildings.addRect(CGRect(x: x + width * 0.2, y: top, width: 44, height: 46))
                buildings.addRect(CGRect(x: x + width * 0.2 + 6, y: top + 46, width: 32, height: 16))
            }
            // Lit windows near the top.
            var wy = top - 50
            while wy > top - 420 {
                var wx = x + 14
                while wx < x + width - 30 {
                    if random.next() < 0.35 {
                        lights.addRect(CGRect(x: wx, y: wy, width: 12, height: 18))
                    }
                    wx += 26
                }
                wy -= 36
            }
            x += width
        }
        let buildingNode = SKShapeNode(path: buildings)
        buildingNode.fillColor = color
        buildingNode.strokeColor = .clear
        node.addChild(buildingNode)
        let lightNode = SKShapeNode(path: lights)
        lightNode.fillColor = windows
        lightNode.strokeColor = .clear
        node.addChild(lightNode)
        return Layer(node: node, depth: depth)
    }
}
