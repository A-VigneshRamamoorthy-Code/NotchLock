import Foundation

/// Plain RGBA colour (components in 0...1) so the core stays free of AppKit.
public struct RGBA: Equatable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}

/// How the cord + handle are drawn. The physics is shared; only the look changes.
public enum CordLook: String, Sendable {
    case brass        // thin tapered cord + round amber bead
    case rope         // thick jute rope + wooden ring handle
    case ballChain    // metal ball-chain (beads) + end knob
    case neon         // glowing cord + bright orb
}

/// All the tuning that gives a cord its feel and look: a lamp-style pull-cord
/// that hangs from the notch under gravity, can be grabbed and pulled, then
/// snaps back and swings on release. Past a pull threshold it arms the lock.
public struct ChainStyle: Equatable, Sendable {
    /// Stable id (used for image caches + persistence).
    public var id: String
    public var look: CordLook

    // --- Rope (Verlet) ---
    public var segments: Int
    public var restLength: Double
    public var maxReach: Double
    public var gravity: Double
    public var chainDamping: Double
    public var tipStiffness: Double
    public var tipDamping: Double
    public var constraintIters: Int
    public var lenStiffness: Double
    public var lenDamping: Double
    /// Ambient horizontal sway acceleration (pt/s²), scaled by emergence — the
    /// "playful" gentle swaying while the cord is out. Zero when tucked ⇒ 0% CPU.
    public var swayAmp: Double

    // --- Look ---
    public var beadRadius: Double
    public var cordBaseWidth: Double
    public var cordTipWidth: Double

    // --- Interaction ---
    public var activationRadius: Double
    public var grabRadius: Double
    public var pullThreshold: Double

    // --- Timing ---
    public var lockDelay: Double

    // --- Palette ---
    public var cord: RGBA
    public var cordHighlight: RGBA
    public var bead: RGBA
    public var beadHighlight: RGBA
    public var outline: RGBA
    public var armed: RGBA

    public init(id: String, look: CordLook, segments: Int, restLength: Double, maxReach: Double,
                gravity: Double, chainDamping: Double, tipStiffness: Double, tipDamping: Double,
                constraintIters: Int, lenStiffness: Double, lenDamping: Double, swayAmp: Double,
                beadRadius: Double, cordBaseWidth: Double, cordTipWidth: Double,
                activationRadius: Double, grabRadius: Double, pullThreshold: Double,
                lockDelay: Double, cord: RGBA, cordHighlight: RGBA, bead: RGBA,
                beadHighlight: RGBA, outline: RGBA, armed: RGBA) {
        self.id = id; self.look = look; self.segments = segments; self.restLength = restLength
        self.maxReach = maxReach; self.gravity = gravity; self.chainDamping = chainDamping
        self.tipStiffness = tipStiffness; self.tipDamping = tipDamping
        self.constraintIters = constraintIters; self.lenStiffness = lenStiffness
        self.lenDamping = lenDamping; self.swayAmp = swayAmp; self.beadRadius = beadRadius
        self.cordBaseWidth = cordBaseWidth; self.cordTipWidth = cordTipWidth
        self.activationRadius = activationRadius; self.grabRadius = grabRadius
        self.pullThreshold = pullThreshold; self.lockDelay = lockDelay
        self.cord = cord; self.cordHighlight = cordHighlight; self.bead = bead
        self.beadHighlight = beadHighlight; self.outline = outline; self.armed = armed
    }

    /// The default look (brass bead pull-cord).
    public static let standard = CordStyle.brass.style
}

/// The selectable cord visuals — switch between them by right-clicking the notch.
public enum CordStyle: String, CaseIterable, Sendable {
    case brass
    case rope
    case ballChain = "ball_chain"
    case neon

    public var displayName: String {
        switch self {
        case .brass: return "Brass Bead"
        case .rope: return "Thick Rope"
        case .ballChain: return "Ball Chain"
        case .neon: return "Neon Cord"
        }
    }

    public var tagline: String {
        switch self {
        case .brass: return "Classic amber pull-bead."
        case .rope: return "Chunky jute rope + wooden ring."
        case .ballChain: return "A metal lamp pull-chain."
        case .neon: return "Glowing and extra bouncy."
        }
    }

    public var emoji: String {
        switch self {
        case .brass: return "🔔"
        case .rope: return "🪢"
        case .ballChain: return "⛓️"
        case .neon: return "💡"
        }
    }

    /// The full tuning + palette for this look.
    public var style: ChainStyle {
        switch self {
        case .brass:
            return ChainStyle(
                id: rawValue, look: .brass,
                segments: 10, restLength: 122, maxReach: 300, gravity: 2000,
                chainDamping: 0.95, tipStiffness: 420, tipDamping: 18, constraintIters: 8,
                lenStiffness: 150, lenDamping: 17, swayAmp: 150,
                beadRadius: 12.5, cordBaseWidth: 5.4, cordTipWidth: 3.4,
                activationRadius: 190, grabRadius: 36, pullThreshold: 130, lockDelay: 2.6,
                cord: RGBA(0.78, 0.70, 0.44), cordHighlight: RGBA(0.95, 0.90, 0.66),
                bead: RGBA(0.86, 0.72, 0.36), beadHighlight: RGBA(1.0, 0.93, 0.72),
                outline: RGBA(0.20, 0.17, 0.10), armed: RGBA(1.0, 0.42, 0.36))
        case .rope:
            // Heavier: more segments, thicker, a touch more gravity, calmer sway.
            return ChainStyle(
                id: rawValue, look: .rope,
                segments: 12, restLength: 128, maxReach: 306, gravity: 2200,
                chainDamping: 0.955, tipStiffness: 440, tipDamping: 18, constraintIters: 9,
                lenStiffness: 165, lenDamping: 18, swayAmp: 110,
                beadRadius: 19, cordBaseWidth: 13, cordTipWidth: 10,
                activationRadius: 194, grabRadius: 44, pullThreshold: 132, lockDelay: 2.6,
                cord: RGBA(0.80, 0.63, 0.36), cordHighlight: RGBA(0.92, 0.79, 0.52),
                bead: RGBA(0.62, 0.44, 0.24), beadHighlight: RGBA(0.82, 0.63, 0.38),
                outline: RGBA(0.28, 0.19, 0.09), armed: RGBA(0.98, 0.44, 0.34))
        case .ballChain:
            // Lots of little beads; light and lively.
            return ChainStyle(
                id: rawValue, look: .ballChain,
                segments: 12, restLength: 120, maxReach: 300, gravity: 1950,
                chainDamping: 0.95, tipStiffness: 420, tipDamping: 18, constraintIters: 8,
                lenStiffness: 150, lenDamping: 16, swayAmp: 170,
                beadRadius: 12, cordBaseWidth: 3.0, cordTipWidth: 2.4,
                activationRadius: 190, grabRadius: 36, pullThreshold: 130, lockDelay: 2.6,
                cord: RGBA(0.66, 0.68, 0.72), cordHighlight: RGBA(0.92, 0.94, 0.98),
                bead: RGBA(0.74, 0.76, 0.80), beadHighlight: RGBA(0.98, 0.99, 1.0),
                outline: RGBA(0.22, 0.23, 0.26), armed: RGBA(1.0, 0.44, 0.40))
        case .neon:
            // Bouncier + big ambient sway; glowing.
            return ChainStyle(
                id: rawValue, look: .neon,
                segments: 10, restLength: 124, maxReach: 302, gravity: 1750,
                chainDamping: 0.96, tipStiffness: 400, tipDamping: 16, constraintIters: 8,
                lenStiffness: 140, lenDamping: 14, swayAmp: 230,
                beadRadius: 13.5, cordBaseWidth: 5.0, cordTipWidth: 3.6,
                activationRadius: 200, grabRadius: 38, pullThreshold: 128, lockDelay: 2.6,
                cord: RGBA(0.30, 0.95, 0.92), cordHighlight: RGBA(0.80, 1.0, 0.99),
                bead: RGBA(0.32, 0.98, 0.90), beadHighlight: RGBA(0.90, 1.0, 1.0),
                outline: RGBA(0.05, 0.30, 0.32), armed: RGBA(1.0, 0.36, 0.62))
        }
    }

    public init?(id: String) {
        guard let s = CordStyle(rawValue: id) else { return nil }
        self = s
    }
}
