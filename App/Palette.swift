import SpriteKit
import GrappleCore

enum Palette {
    static let background = SKColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1)
    static let grappleable = SKColor(red: 0.95, green: 0.55, blue: 0.20, alpha: 1)
    static let solid = SKColor(red: 0.33, green: 0.35, blue: 0.40, alpha: 1)
    static let stickman = SKColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
    static let crashed = SKColor(red: 0.85, green: 0.20, blue: 0.20, alpha: 1)
    static let rope = SKColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1)
    static let miss = SKColor(red: 0.85, green: 0.20, blue: 0.20, alpha: 0.8)
    static let boost = SKColor(red: 0.20, green: 0.55, blue: 0.95, alpha: 1)
    static let finish = SKColor(red: 0.20, green: 0.65, blue: 0.35, alpha: 1)
}

extension CGPoint {
    init(_ v: Vec2) { self.init(x: v.x, y: v.y) }
}

extension Vec2 {
    init(_ p: CGPoint) { self.init(Double(p.x), Double(p.y)) }
}
