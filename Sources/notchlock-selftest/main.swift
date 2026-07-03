import CoreGraphics
import Foundation
import NotchLockCore

// Minimal test harness — Command Line Tools ship no XCTest, so we run plain
// assertions and exit non-zero on failure.

var failures = 0
var checks = 0

func check(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    checks += 1
    if !condition {
        failures += 1
        print("  ✗ FAIL: \(message)  (\(file):\(line))")
    }
}

func approx(_ a: Double, _ b: Double, _ tol: Double = 0.5) -> Bool { abs(a - b) <= tol }
func group(_ name: String, _ body: () -> Void) { print("• \(name)"); body() }

let dt = 1.0 / 60.0
func run(_ engine: inout ChainEngine, engaged: Bool, seconds: Double) {
    var t = 0.0
    while t < seconds { engine.update(dt: dt, engaged: engaged); t += dt }
}

let shoulder = CGPoint(x: 260, y: 360)
func makeEngine() -> ChainEngine { ChainEngine(shoulder: shoulder, style: .standard) }
let style = ChainStyle.standard

group("Spring") {
    let spring = Spring(stiffness: 200, damping: 20)
    var p = 0.0, v = 0.0
    for _ in 0..<600 { (p, v) = spring.step(position: p, velocity: v, target: 100, dt: dt) }
    check(approx(p, 100), "spring converges (p=\(p))")
    var p2 = 0.0, v2 = 0.0
    let stiff = Spring(stiffness: 300, damping: 12)
    for _ in 0..<200 { (p2, v2) = stiff.step(position: p2, velocity: v2, target: 50, dt: 0.25) }
    check(!p2.isNaN && abs(p2) < 1000, "spring stable with large dt (p=\(p2))")
}

group("NotchGeometry") {
    let screen = CGRect(x: 0, y: 0, width: 1280, height: 832)
    let auxL = CGRect(x: 0, y: 800, width: 540, height: 32)
    let auxR = CGRect(x: 740, y: 800, width: 540, height: 32)
    let g = NotchGeometry.compute(screenFrame: screen, safeAreaTop: 32, auxLeft: auxL, auxRight: auxR)
    check(g.hasNotch, "detects notch between aux areas")
    check(approx(Double(g.notchRect.width), 200, 0.01), "notch width")
    check(approx(Double(g.shoulder.x), 640, 0.01), "shoulder centred")
    let f = NotchGeometry.compute(screenFrame: screen, safeAreaTop: 0, auxLeft: nil, auxRight: nil)
    check(!f.hasNotch, "fallback reports no hardware notch")
}

group("ChainEngine — reveal & drop physics") {
    var hidden = makeEngine()
    check(Double(hidden.state.emergence) == 0, "starts hidden (tucked in the notch)")
    check(hidden.isMotionless, "starts motionless → link can stay paused")
    check(hidden.state.nodes.count == style.segments, "cord has \(style.segments) nodes")
    hidden.update(dt: dt, engaged: false)
    check(hidden.isMotionless, "stays motionless while disengaged")

    var emerged = makeEngine()
    run(&emerged, engaged: true, seconds: 2.0)
    check(Double(emerged.state.emergence) > 0.9, "drops out of the notch when the cursor is near")
    let drop = Double(shoulder.y - emerged.beadPosition.y)
    check(drop > style.restLength * 0.85, "hangs ~restLength below the notch (drop=\(drop))")
    check(abs(Double(emerged.beadPosition.x - shoulder.x)) < 10, "hangs straight down (gravity)")

    // Retract when the cursor leaves.
    run(&emerged, engaged: false, seconds: 3.0)
    check(Double(emerged.state.emergence) < 0.05, "tucks away when the cursor leaves")
    check(emerged.isMotionless, "settles motionless after tucking")
}

group("ChainEngine — grab / drag / release") {
    var e = makeEngine()
    run(&e, engaged: true, seconds: 1.2)

    // Not grabbable far from the bead; grabbable at the bead.
    check(e.grab(at: CGPoint(x: shoulder.x + 400, y: 0)) == false, "can't grab far from the bead")
    check(e.grab(at: e.beadPosition), "grabs the bead when close")
    check(e.isGrabbed, "is grabbed")

    // Drag is clamped to maxReach.
    e.drag(to: CGPoint(x: shoulder.x, y: shoulder.y - 100000))
    e.update(dt: dt, engaged: true)
    let reach = hypot(Double(e.beadPosition.x - shoulder.x), Double(e.beadPosition.y - shoulder.y))
    check(reach <= style.maxReach + 2, "pull is clamped to maxReach (reach=\(reach))")

    // Can't grab when tucked away.
    var tucked = makeEngine()
    run(&tucked, engaged: false, seconds: 0.5)
    check(tucked.grab(at: tucked.beadPosition) == false, "can't grab the cord while it's hidden")
}

group("ChainEngine — pull threshold fires once") {
    // A deep pull past the threshold arms the lock.
    var deep = makeEngine()
    run(&deep, engaged: true, seconds: 1.0)
    check(deep.grab(at: deep.beadPosition), "grab for deep pull")
    let deepTargetY = shoulder.y - CGFloat(style.restLength + style.pullThreshold + 30)
    for _ in 0..<60 {
        deep.drag(to: CGPoint(x: shoulder.x, y: deepTargetY))
        deep.update(dt: dt, engaged: true)
    }
    check(deep.state.armed, "armed while pulled past the threshold")
    check(deep.release() == true, "release past threshold triggers the lock")
    check(deep.release() == false, "a second release does not re-trigger")

    // After release it recoils/swings, then returns to rest. (Held steady at the
    // bottom, velocities are ~0 at the release instant; the swing appears on the
    // next ticks as the length-spring snaps back.)
    let tipAtRelease = deep.beadPosition
    run(&deep, engaged: true, seconds: 0.25)
    let swung = hypot(Double(deep.beadPosition.x - tipAtRelease.x),
                      Double(deep.beadPosition.y - tipAtRelease.y))
    check(swung > 20, "recoils/swings up after release (Δ=\(swung))")
    check(!deep.isMotionless, "still swinging shortly after release")
    run(&deep, engaged: true, seconds: 4.0)
    check(deep.isMotionless, "settles after swinging")
    let backDrop = Double(shoulder.y - deep.beadPosition.y)
    check(approx(backDrop, style.restLength, 12), "returns to the rest position (drop=\(backDrop))")

    // A shallow pull does NOT fire.
    var shallow = makeEngine()
    run(&shallow, engaged: true, seconds: 1.0)
    _ = shallow.grab(at: shallow.beadPosition)
    let shallowY = shoulder.y - CGFloat(style.restLength + 55)
    for _ in 0..<40 {
        shallow.drag(to: CGPoint(x: shoulder.x, y: shallowY))
        shallow.update(dt: dt, engaged: true)
    }
    check(shallow.state.armed == false, "not armed for a shallow pull")
    check(shallow.release() == false, "shallow pull does not lock")
}

group("ChainEngine — stability") {
    var huge = makeEngine()
    run(&huge, engaged: true, seconds: 0.5)
    _ = huge.grab(at: huge.beadPosition)
    huge.drag(to: CGPoint(x: shoulder.x + 500, y: shoulder.y - 500))
    huge.update(dt: 5.0, engaged: true)
    let d = hypot(Double(huge.beadPosition.x - shoulder.x), Double(huge.beadPosition.y - shoulder.y))
    check(!huge.beadPosition.x.isNaN && !huge.beadPosition.y.isNaN, "huge dt: finite")
    check(d <= style.maxReach + 3, "huge dt: still within maxReach (\(d))")
}

group("ChainRenderer") {
    var e = makeEngine()
    run(&e, engaged: true, seconds: 1.0)
    let b = ChainRenderer.bounds(of: e.state, style: style)
    check(b.width > 0 && b.height > 0 && !b.width.isNaN, "cord bounds finite & non-empty")
    let icon = ChainRenderer.icon(for: style, size: CGSize(width: 22, height: 30))
    check(icon != nil && (icon?.width ?? 0) > 0, "menu icon renders with pixels")
    let app = ChainRenderer.appIcon(pt: 256, scale: 1)
    check(app != nil && app?.width == 256, "app icon renders at 256px")
}

print("\n\(checks - failures)/\(checks) checks passed.")
if failures > 0 { print("❌ \(failures) failure(s)."); exit(1) }
print("✅ All checks passed.")
exit(0)
