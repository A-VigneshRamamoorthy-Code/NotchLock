import Foundation

/// Plain RGBA colour (components in 0...1) so the core stays free of AppKit.
public struct RGBA: Equatable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}

/// All the tuning that gives NotchLock its feel: a lamp-style pull-cord that
/// hangs from the notch under gravity, can be grabbed and pulled, then snaps
/// back and swings on release. Past a pull threshold it arms the screen-lock.
public struct ChainStyle: Equatable, Sendable {
    // --- Rope (Verlet) ---
    /// Chain nodes including the pinned base at the notch.
    public var segments: Int
    /// Total length of the cord when hanging at rest (points).
    public var restLength: Double
    /// Maximum length the cord can be stretched to while pulling (points).
    public var maxReach: Double
    /// Downward acceleration — the "drop physics".
    public var gravity: Double
    /// Verlet inertia for the free nodes (higher ⇒ more, longer swinging).
    public var chainDamping: Double
    /// How hard the tip chases the hand while grabbed.
    public var tipStiffness: Double
    /// Velocity retention of the tip while grabbed (0…1).
    public var tipDamping: Double
    /// Distance-constraint relaxation iterations per step.
    public var constraintIters: Int
    /// Springiness of the cord's *length*: it stretches toward the hand while
    /// pulled and snaps back (underdamped ⇒ a satisfying recoil) on release.
    public var lenStiffness: Double
    public var lenDamping: Double

    // --- Look ---
    /// Radius of the round pull-knob / bead at the tip (points).
    public var beadRadius: Double
    /// Cord half-thickness at the notch and at the bead.
    public var cordBaseWidth: Double
    public var cordTipWidth: Double

    // --- Interaction ---
    /// Cursor proximity to the notch that reveals the cord (points).
    public var activationRadius: Double
    /// How close to the bead a click counts as a grab (points).
    public var grabRadius: Double
    /// Vertical pull below rest that arms/triggers the lock (points).
    public var pullThreshold: Double

    // --- Timing ---
    /// Seconds between a successful pull and the screen locking.
    public var lockDelay: Double

    // --- Palette ---
    public var cord: RGBA
    public var cordHighlight: RGBA
    public var bead: RGBA
    public var beadHighlight: RGBA
    public var outline: RGBA
    /// Glow used once the pull passes the arming threshold.
    public var armed: RGBA

    public init(segments: Int, restLength: Double, maxReach: Double, gravity: Double,
                chainDamping: Double, tipStiffness: Double, tipDamping: Double,
                constraintIters: Int, lenStiffness: Double, lenDamping: Double,
                beadRadius: Double, cordBaseWidth: Double, cordTipWidth: Double,
                activationRadius: Double, grabRadius: Double, pullThreshold: Double,
                lockDelay: Double, cord: RGBA, cordHighlight: RGBA, bead: RGBA,
                beadHighlight: RGBA, outline: RGBA, armed: RGBA) {
        self.segments = segments; self.restLength = restLength; self.maxReach = maxReach
        self.gravity = gravity; self.chainDamping = chainDamping
        self.tipStiffness = tipStiffness; self.tipDamping = tipDamping
        self.constraintIters = constraintIters; self.lenStiffness = lenStiffness
        self.lenDamping = lenDamping; self.beadRadius = beadRadius
        self.cordBaseWidth = cordBaseWidth; self.cordTipWidth = cordTipWidth
        self.activationRadius = activationRadius; self.grabRadius = grabRadius
        self.pullThreshold = pullThreshold; self.lockDelay = lockDelay
        self.cord = cord; self.cordHighlight = cordHighlight; self.bead = bead
        self.beadHighlight = beadHighlight; self.outline = outline; self.armed = armed
    }

    /// The default lamp-cord look and feel.
    public static let standard = ChainStyle(
        segments: 10,
        restLength: 122,
        maxReach: 300,
        gravity: 2000,
        chainDamping: 0.95,
        tipStiffness: 420,
        tipDamping: 18,
        constraintIters: 8,
        lenStiffness: 150,
        lenDamping: 17,
        beadRadius: 12.5,
        cordBaseWidth: 5.4,
        cordTipWidth: 3.4,
        activationRadius: 168,
        grabRadius: 34,
        pullThreshold: 130,
        lockDelay: 2.6,
        // Warm brass cord + amber bead, like a real pull-chain switch.
        cord: RGBA(0.78, 0.70, 0.44),
        cordHighlight: RGBA(0.95, 0.90, 0.66),
        bead: RGBA(0.86, 0.72, 0.36),
        beadHighlight: RGBA(1.0, 0.93, 0.72),
        outline: RGBA(0.20, 0.17, 0.10),
        armed: RGBA(1.0, 0.42, 0.36)
    )
}
