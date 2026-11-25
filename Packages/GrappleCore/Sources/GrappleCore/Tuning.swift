/// Every feel parameter lives here so the debug overlay can change it live.
/// Units: world points and seconds.
public struct Tuning: Equatable, Codable, Sendable {
    public var gravity: Double = 1800
    /// Fraction of velocity lost per second.
    public var airDrag: Double = 0.1
    public var maxSpeed: Double = 2600
    /// Furthest a rope shot can reach.
    public var ropeRange: Double = 750
    public var minRopeLength: Double = 40
    /// Taps within this distance of a grappleable surface snap to it.
    public var aimAssistRadius: Double = 120
    /// If the direct shot misses, rays are tried up to this many degrees either side of the aim.
    public var aimAssistAngleDegrees: Double = 18
    public var torsoRadius: Double = 16
    /// Hitting a surface faster than this (along its normal) is a crash.
    public var crashImpactSpeed: Double = 1100
    /// Fraction of sliding speed lost per second while touching a surface.
    public var surfaceFriction: Double = 6

    public init() {}

    public static let `default` = Tuning()
}
