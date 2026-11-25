/// Every feel parameter lives here so the debug overlay can change it live.
/// Units: world points and seconds.
public struct Tuning: Equatable, Codable, Sendable {
    public var gravity: Double = 1000
    /// Gravity is multiplied by this while the rope is taut: snappier swings without shortening airtime.
    public var swingGravityMultiplier: Double = 1.6
    /// Fraction of velocity lost per second.
    public var airDrag: Double = 0.1
    public var maxSpeed: Double = 3750
    /// Furthest a rope shot can reach.
    public var ropeRange: Double = 840
    public var minRopeLength: Double = 45
    /// On attaching, speed toward the anchor is topped up to at least this, so a shot always yanks you into a swing.
    public var attachTugSpeed: Double = 750
    /// Taps within this distance of a grappleable surface snap to it.
    public var aimAssistRadius: Double = 280
    /// If the direct shot misses, rays are tried up to this many degrees either side of the aim.
    public var aimAssistAngleDegrees: Double = 18
    public var torsoRadius: Double = 16
    /// How strongly arms and legs are pulled back toward their rest pose while alive (per second).
    public var limbStiffness: Double = 10
    /// Fraction of limb speed lost per second.
    public var limbDamping: Double = 1.5
    /// Rope length change per point the holding finger slides along the rope (toward the stickman = shorter).
    public var reelRatio: Double = 1.5
    /// Letting go of a taut rope while moving at least this fast, heading upward within the angle window, boosts.
    public var boostMinSpeed: Double = 500
    public var boostImpulse: Double = 350
    /// Upward speed added whenever you let go of a taut rope while rising (on top of any boost).
    public var releaseLift: Double = 250
    /// Boost window, in degrees above horizontal.
    public var boostMinAngleDegrees: Double = 20
    public var boostMaxAngleDegrees: Double = 75
    /// Hitting a surface faster than this (along its normal) is a crash.
    public var crashImpactSpeed: Double = 2300
    /// Fraction of sliding speed lost per second while touching a surface.
    public var surfaceFriction: Double = 6

    public init() {}

    public static let `default` = Tuning()
}
