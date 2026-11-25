import Foundation

/// A 2D vector in world units (points). y points up, matching SpriteKit.
public struct Vec2: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)

    public var lengthSquared: Double { x * x + y * y }
    public var length: Double { lengthSquared.squareRoot() }

    /// Unit vector in the same direction, or `.zero` for a zero-length vector.
    public var normalized: Vec2 {
        let l = length
        return l > 1e-9 ? Vec2(x / l, y / l) : .zero
    }

    /// Rotated 90° counter-clockwise.
    public var perpendicular: Vec2 { Vec2(-y, x) }

    public func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }
    /// z of the 3D cross product: positive when `o` is counter-clockwise from `self`.
    public func cross(_ o: Vec2) -> Double { x * o.y - y * o.x }
    public func distance(to o: Vec2) -> Double { (self - o).length }

    /// Rotated counter-clockwise by `radians`.
    public func rotated(by radians: Double) -> Vec2 {
        let c = cos(radians), s = sin(radians)
        return Vec2(x * c - y * s, x * s + y * c)
    }

    public static func + (l: Vec2, r: Vec2) -> Vec2 { Vec2(l.x + r.x, l.y + r.y) }
    public static func - (l: Vec2, r: Vec2) -> Vec2 { Vec2(l.x - r.x, l.y - r.y) }
    public static prefix func - (v: Vec2) -> Vec2 { Vec2(-v.x, -v.y) }
    public static func * (v: Vec2, s: Double) -> Vec2 { Vec2(v.x * s, v.y * s) }
    public static func * (s: Double, v: Vec2) -> Vec2 { Vec2(v.x * s, v.y * s) }
    public static func / (v: Vec2, s: Double) -> Vec2 { Vec2(v.x / s, v.y / s) }
}
