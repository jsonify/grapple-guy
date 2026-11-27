/// Every feel parameter lives here so the debug overlay can change it live.
/// Units: world points and seconds.
public struct Tuning: Equatable, Codable, Sendable {
    public var gravity: Double = 1000
    /// Gravity is multiplied by this while the rope is taut: snappier swings without shortening airtime.
    public var swingGravityMultiplier: Double = 1.6
    /// Fraction of velocity lost per second.
    public var airDrag: Double = 0.1
    public var maxSpeed: Double = 3750
    /// Minimum rope reach; the game stretches it to `ropeRangeScreenFactor` × the distance to the screen edge.
    public var ropeRange: Double = 840
    /// Rope shots fly this multiple of the distance to the screen edge in the aimed direction (1.1 = 10% past it).
    public var ropeRangeScreenFactor: Double = 1.1
    /// How fast the rope tip flies out.
    public var ropeTipSpeed: Double = 3000
    public var minRopeLength: Double = 45
    /// On attaching, speed toward the anchor is topped up to at least this, so a shot always yanks you into a swing.
    public var attachTugSpeed: Double = 750
    /// Taps within this distance of a grappleable surface snap to it.
    public var aimAssistRadius: Double = 280
    /// If the direct shot misses, rays are tried up to this many degrees either side of the aim.
    public var aimAssistAngleDegrees: Double = 18
    /// When the direct shot hits a wall, the fan widens to this many degrees.
    public var aimAssistBlockedAngleDegrees: Double = 35
    public var torsoRadius: Double = 16
    /// Sand: fraction of speed lost per second while touching sand (stops you dead).
    public var sandFriction: Double = 30
    /// Sand: the next rope's attach tug is multiplied by this when fired from sand ("blast out").
    public var sandTugFactor: Double = 0.4
    /// Multiplies each hole's wind.
    public var windStrength: Double = 1
    /// Gems are collected when the torso comes this close.
    public var gemPickupRadius: Double = 40
    /// How strongly arms and legs are pulled back toward their rest pose while alive (per second).
    public var limbStiffness: Double = 10
    /// Fraction of limb speed lost per second.
    public var limbDamping: Double = 1.5
    /// Chance (0…1) of spinning when letting go while flying upward fast. Boosted releases always spin.
    public var flipChance: Double = 0.3
    /// Minimum speed at release to start spinning.
    public var flipMinSpeed: Double = 700
    /// Spinning keeps going while airborne; its rate is speed ÷ this, in rotations per second…
    public var spinSpeedPerRotation: Double = 900
    /// …clamped to this range (rotations per second).
    public var spinMinRotations: Double = 0.9
    public var spinMaxRotations: Double = 2
    /// Holding the rope this long (seconds) starts retracting it, so quick taps still swing.
    public var retractDelay: Double = 0.2
    /// Rope length retracted per second while holding.
    public var retractSpeed: Double = 700
    /// Retracting stops at this rope length.
    public var retractMinLength: Double = 80
    /// 0…1: how much of the swing speed-up from shortening the rope is kept (1 = full angular momentum).
    public var retractMomentumCarry: Double = 0.5
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

    // MARK: Game feel (presentation only; issue #20)

    /// How fast game time runs compared with real time (1 = full speed). Below 1 the whole game, bots included,
    /// plays in gentle slow motion: every swing traces the same path, just with more time to read it and react.
    /// The game scene scales frame time by this before handing it to the player's and the bots' simulations.
    public var gameSpeed: Double = 0.8

    /// Freeze-frame length on a crash, in seconds (half of it on finishing).
    public var hitStopSeconds: Double = 0.1
    /// Extra view (as a fraction) the camera zooms out at high speed.
    public var speedZoom: Double = 0.2
    /// Speed at which the zoom-out is full.
    public var speedZoomFullSpeed: Double = 2500
    /// Screen-shake strength on a crash, in points.
    public var screenShake: Double = 16

    public init() {}

    public static let `default` = Tuning()
}
