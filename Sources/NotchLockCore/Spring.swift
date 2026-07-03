import Foundation

/// A damped harmonic oscillator used to chase a target value smoothly.
///
/// Integrated with semi-implicit (symplectic) Euler and adaptive sub-stepping so
/// it stays stable even with large or irregular frame deltas. Used here for the
/// string's "emergence" (peek out / tuck away) motion.
public struct Spring: Equatable, Sendable {
    public var stiffness: Double
    public var damping: Double
    public var mass: Double

    public init(stiffness: Double, damping: Double, mass: Double = 1) {
        self.stiffness = stiffness
        self.damping = damping
        self.mass = max(0.0001, mass)
    }

    /// Advance `position`/`velocity` toward `target` over `dt` seconds.
    /// - Returns: the updated position and velocity.
    public func step(position: Double,
                     velocity: Double,
                     target: Double,
                     dt: Double,
                     substeps: Int = 2) -> (position: Double, velocity: Double) {
        guard dt > 0 else { return (position, velocity) }
        var p = position
        var v = velocity
        let maxStep = 1.0 / 180.0
        let n = min(64, max(substeps, Int((dt / maxStep).rounded(.up))))
        let h = dt / Double(n)
        for _ in 0..<n {
            let force = stiffness * (target - p) - damping * v
            let a = force / mass
            v += a * h
            p += v * h
        }
        return (p, v)
    }
}
