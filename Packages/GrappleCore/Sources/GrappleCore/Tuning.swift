/// Every feel parameter lives here so the debug overlay can change it live.
/// Units: world points and seconds.
public struct Tuning: Equatable, Codable, Sendable {
    public var gravity: Double = 1000
    /// Gravity is multiplied by this while the rope is taut: snappier swings without shortening airtime.
    public var swingGravityMultiplier: Double = 1.6
    /// Fraction of velocity lost per second.
    public var airDrag: Double = 0.1
    public var maxSpeed: Double = 2600
    /// Furthest a rope shot can reach.
    public var ropeRange: Double = 750
    public var minRopeLength: Double = 40
    /// On attaching, speed toward the anchor is topped up to at least this, so a shot always yanks you into a swing.
    public var attachTugSpeed: Double = 750
    /// Taps within this distance of a grappleable surface snap to it.
    public var aimAssistRadius: Double = 180
    /// If the direct shot misses, rays are tried up to this many degrees either side of the aim.
    public var aimAssistAngleDegrees: Double = 18
    public var torsoRadius: Double = 16
    /// Rope length change per point the holding finger slides along the rope (toward the stickman = shorter).
    public var reelRatio: Double = 1.5
    /// Letting go of a taut rope while moving at least this fast, heading upward within the angle window, boosts.
    public var boostMinSpeed: Double = 500
    public var boostImpulse: Double = 350
    /// Boost window, in degrees above horizontal.
    public var boostMinAngleDegrees: Double = 5
    public var boostMaxAngleDegrees: Double = 75
    /// Hitting a surface faster than this (along its normal) is a crash.
    public var crashImpactSpeed: Double = 1100
    /// Fraction of sliding speed lost per second while touching a surface.
    public var surfaceFriction: Double = 6

    public init() {}

    public static let `default` = Tuning()
}
