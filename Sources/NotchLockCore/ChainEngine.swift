import CoreGraphics
import Foundation

/// The animated state of the pull-cord at one instant.
public struct ChainState: Equatable, Sendable {
    /// Cord nodes from the pinned base (notch) to the bead tip.
    public var nodes: [CGPoint]
    /// How far the cord has dropped out of the notch, 0 ... 1.
    public var emergence: CGFloat
    /// Orientation of the bead (radians) — direction of the last segment.
    public var tipRotation: CGFloat
    /// True while the user is holding the bead.
    public var grabbed: Bool
    /// True while the current pull is past the arming threshold.
    public var armed: Bool

    public var tip: CGPoint { nodes.last ?? .zero }

    public init(nodes: [CGPoint]) {
        self.nodes = nodes
        emergence = 0
        tipRotation = -.pi / 2
        grabbed = false
        armed = false
    }
}

/// Pure simulation of a lamp-style pull-cord hanging from the notch.
///
/// The cord is a rigid Verlet rope pinned at the notch, so it hangs straight and
/// swings like a pendulum under gravity. To *reveal / hide* it, the pinned base
/// is translated vertically (the rope slides down out of the notch, or up behind
/// the top edge) — this avoids ever collapsing the rope. The rope's *length* is
/// springy: while you hold and pull the bead it stretches toward your hand (up
/// to `maxReach`); on release the length snaps back to rest, so it recoils and
/// swings. Deterministic and AppKit-free so it can be unit-tested headlessly.
public struct ChainEngine {
    public private(set) var state: ChainState
    public var style: ChainStyle {
        didSet { if style.segments != segCount { rebuild() } }
    }
    /// The notch anchor (bottom-centre of the notch, above the top edge).
    public var shoulder: CGPoint

    private var prevNodes: [CGPoint]
    private var segCount: Int
    private var time: Double = 0
    private var emergence: Double = 0
    private var emergenceVel: Double = 0
    private var grabbed = false
    private var tipTarget: CGPoint?
    private var restLenCur: Double
    private var restLenVel: Double = 0
    private var maxPullDepth: Double = 0

    /// How far the pinned base is lifted above the notch while fully tucked, so
    /// the whole hanging rope clears the visible top edge.
    private var hideRise: Double { style.restLength + 44 }

    public init(shoulder: CGPoint, style: ChainStyle) {
        self.shoulder = shoulder
        self.style = style
        self.segCount = style.segments
        self.restLenCur = style.restLength
        // Initialise hanging straight down from the tucked (raised) anchor so the
        // rope starts fully settled and motionless.
        let eff = CGPoint(x: shoulder.x, y: shoulder.y + CGFloat(style.restLength + 44))
        let seg = style.restLength / Double(max(1, style.segments - 1))
        var nodes = [CGPoint]()
        nodes.reserveCapacity(style.segments)
        for i in 0..<style.segments {
            nodes.append(CGPoint(x: eff.x, y: eff.y - CGFloat(Double(i) * seg)))
        }
        self.state = ChainState(nodes: nodes)
        self.prevNodes = nodes
    }

    public mutating func reset() {
        self = ChainEngine(shoulder: shoulder, style: style)
    }

    private mutating func rebuild() {
        self = ChainEngine(shoulder: shoulder, style: style)
    }

    // MARK: - Derived positions

    public var beadPosition: CGPoint { state.tip }

    /// The effective pinned point for the current emergence (raised when tucked).
    private func effectiveShoulder(_ em: Double) -> CGPoint {
        CGPoint(x: shoulder.x, y: shoulder.y + CGFloat((1 - em) * hideRise))
    }

    /// Y of the bead when the cord hangs straight at rest (current emergence).
    public var restTipY: CGFloat { effectiveShoulder(emergence).y - CGFloat(style.restLength) }

    /// How far (points) the bead is currently pulled below its rest position.
    public var currentPullDepth: Double { max(0, Double(restTipY - state.tip.y)) }

    public var isGrabbed: Bool { grabbed }
    public var emergenceValue: Double { emergence }

    // MARK: - Interaction

    /// Try to grab the bead near `p`. Returns whether it caught. Only grabbable
    /// once the cord has dropped far enough to be visible.
    @discardableResult
    public mutating func grab(at p: CGPoint) -> Bool {
        guard emergence > 0.45 else { return false }
        let tip = state.tip
        let d = hypot(Double(p.x - tip.x), Double(p.y - tip.y))
        guard d <= style.grabRadius else { return false }
        grabbed = true
        tipTarget = p
        maxPullDepth = 0
        return true
    }

    /// While grabbed, move the bead toward `p`.
    public mutating func drag(to p: CGPoint) {
        guard grabbed else { return }
        tipTarget = p
    }

    /// Release the bead. The rope length snaps back to rest, so it recoils and
    /// swings. Returns `true` when the maximum pull passed the arming threshold
    /// (i.e. the caller should lock the screen).
    @discardableResult
    public mutating func release() -> Bool {
        guard grabbed else { return false }
        let triggered = maxPullDepth >= style.pullThreshold
        grabbed = false
        tipTarget = nil
        maxPullDepth = 0
        return triggered
    }

    // MARK: - Simulation

    public mutating func update(dt: Double, engaged: Bool) {
        let h = min(max(dt, 0), 1.0 / 30.0)
        time += h
        let n = segCount

        // --- Emergence (critically damped drop in / tuck out of the notch) ---
        let emTarget: Double = (grabbed || engaged) ? 1 : 0
        let emForce = 150.0 * (emTarget - emergence) - 24.0 * emergenceVel
        emergenceVel += emForce * h
        emergence = min(1, max(0, emergence + emergenceVel * h))
        state.emergence = CGFloat(emergence)

        let eff = effectiveShoulder(emergence)

        // Clamp the hand target to maxReach so a wild target can't fling the tip.
        var effTarget = tipTarget
        if grabbed, let t = tipTarget {
            let dx = Double(t.x - eff.x), dy = Double(t.y - eff.y)
            let d = (dx * dx + dy * dy).squareRoot()
            if d > style.maxReach, d > 0 {
                let k = style.maxReach / d
                effTarget = CGPoint(x: eff.x + CGFloat(dx * k), y: eff.y + CGFloat(dy * k))
            }
        }

        // --- Springy rope length: stretches to the hand while pulled, snaps
        // back to rest on release (⇒ recoil + swing). ---
        let lenTarget: Double
        if grabbed, let t = effTarget {
            let d = hypot(Double(t.x - eff.x), Double(t.y - eff.y))
            lenTarget = min(style.maxReach, max(style.restLength, d))
        } else {
            lenTarget = style.restLength
        }
        let lenForce = style.lenStiffness * (lenTarget - restLenCur) - style.lenDamping * restLenVel
        restLenVel += lenForce * h
        restLenCur += restLenVel * h
        restLenCur = min(style.maxReach * 1.05, max(8, restLenCur))

        let segLen = restLenCur / Double(n - 1)
        let grav = style.gravity * emergence   // no gravity when tucked ⇒ perfectly still

        // --- Verlet integrate the free nodes (base is pinned in constraints) ---
        var nodes = state.nodes
        nodes[0] = eff
        for i in 1..<n {
            let temp = nodes[i]
            var nx = Double(nodes[i].x), ny = Double(nodes[i].y)
            let vx = nx - Double(prevNodes[i].x)
            let vy = ny - Double(prevNodes[i].y)
            if i == n - 1, grabbed, let t = effTarget {
                // Tip chases the hand (spring-damper) while held.
                let damp = max(0.0, 1.0 - style.tipDamping * h)
                let ax = style.tipStiffness * (Double(t.x) - nx)
                let ay = style.tipStiffness * (Double(t.y) - ny)
                nx += vx * damp + ax * h * h
                ny += vy * damp + ay * h * h
            } else {
                // Free rope: inertia + gravity → hangs straight and swings.
                nx += vx * style.chainDamping
                ny += vy * style.chainDamping - grav * h * h
            }
            nodes[i] = CGPoint(x: nx, y: ny)
            prevNodes[i] = temp
        }

        // --- Distance constraints (move both nodes apart, base pinned) ---
        for _ in 0..<max(1, style.constraintIters) {
            nodes[0] = eff
            for i in 1..<n {
                var dx = Double(nodes[i].x - nodes[i - 1].x)
                var dy = Double(nodes[i].y - nodes[i - 1].y)
                var d = (dx * dx + dy * dy).squareRoot()
                if d < 1e-3 { dx = 0; dy = -1; d = 1 }
                let diff = (d - segLen) / d
                if i - 1 == 0 {
                    nodes[i] = CGPoint(x: Double(nodes[i].x) - dx * diff,
                                       y: Double(nodes[i].y) - dy * diff)
                } else {
                    let hx = dx * 0.5 * diff, hy = dy * 0.5 * diff
                    nodes[i - 1] = CGPoint(x: Double(nodes[i - 1].x) + hx,
                                           y: Double(nodes[i - 1].y) + hy)
                    nodes[i] = CGPoint(x: Double(nodes[i].x) - hx,
                                       y: Double(nodes[i].y) - hy)
                }
            }
            nodes[0] = eff
        }
        state.nodes = nodes

        // --- Derived pose ---
        let tip = nodes[n - 1]
        let prev = nodes[n - 2]
        state.tipRotation = CGFloat(atan2(Double(tip.y - prev.y), Double(tip.x - prev.x)))
        state.grabbed = grabbed
        if grabbed { maxPullDepth = max(maxPullDepth, currentPullDepth) }
        state.armed = grabbed && currentPullDepth >= style.pullThreshold
    }

    /// True when the cord is essentially motionless (all node + length + emergence
    /// velocities tiny) and not being held — the renderer can pause the display
    /// link so CPU drops to zero while the cord hangs still (shown) or hidden.
    public var isMotionless: Bool {
        guard !grabbed else { return false }
        var maxV = 0.0
        for i in 1..<segCount {
            let v = hypot(Double(state.nodes[i].x - prevNodes[i].x),
                          Double(state.nodes[i].y - prevNodes[i].y))
            maxV = max(maxV, v)
        }
        return maxV < 0.08 && abs(emergenceVel) < 0.05 && abs(restLenVel) < 0.6
    }
}
