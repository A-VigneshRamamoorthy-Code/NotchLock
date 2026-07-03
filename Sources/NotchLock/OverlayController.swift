import AppKit
import NotchLockCore

/// Owns the overlay window + cord view and maps the global cursor into the
/// cord's coordinate space. The cord hangs from a fixed point (the notch
/// centre) like a real lamp pull.
final class OverlayController {
    let window: OverlayWindow
    let chainView: ChainView
    private(set) var geometry: NotchGeometry
    private var style: ChainStyle
    private let notchMinX: CGFloat
    private let notchMaxX: CGFloat
    private let activationRefY: CGFloat

    /// Whether the overlay is currently interactive (only while over the bead).
    private var interactive = false
    /// Whether we're currently showing a hand cursor (so we can reset it).
    private var showingHand = false

    init(screen: NSScreen, style: ChainStyle) {
        self.style = style
        let geo = OverlayController.computeGeometry(for: screen)
        self.geometry = geo
        let frame = OverlayController.windowFrame(for: screen, geometry: geo)
        self.window = OverlayWindow(contentRect: frame)

        // Notch span (view coords), slightly inset — used for activation distance.
        let inset: CGFloat = 12
        var minX = geo.notchRect.minX - frame.minX + inset
        var maxX = geo.notchRect.maxX - frame.minX - inset
        if maxX - minX < 24 {
            let mid = geo.shoulder.x - frame.minX
            minX = mid - 30; maxX = mid + 30
        }
        self.notchMinX = minX
        self.notchMaxX = maxX
        self.activationRefY = geo.shoulder.y - frame.minY

        // Anchor just above the visible top edge so the cord is clipped flush
        // where it enters the notch; its x now follows the cursor (see ChainView).
        let shoulderY = frame.height + 16
        self.chainView = ChainView(frame: NSRect(origin: .zero, size: frame.size),
                                   notchMinX: minX, notchMaxX: maxX,
                                   shoulderY: shoulderY, style: style)
        window.contentView = chainView
    }

    func show() { window.orderFrontRegardless() }
    func close() { window.orderOut(nil); window.close() }

    /// Live-swap the cord visual.
    func updateStyle(_ newStyle: ChainStyle) {
        style = newStyle
        chainView.style = newStyle
        chainView.resume()
    }

    // MARK: - Cursor mapping

    private func toView(_ global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - window.frame.minX, y: global.y - window.frame.minY)
    }

    /// Update engagement + the drop position from the cursor's location, and make
    /// the overlay interactive ONLY while the cursor is over the bead (so it can
    /// be grabbed) — click-through everywhere else. Also drives the hand cursor.
    func handleMouseMoved(globalPoint p: CGPoint) {
        let v = toView(p)
        chainView.cursorXView = v.x           // drop the cord in line with the pointer
        let clampedX = min(max(v.x, notchMinX), notchMaxX)
        let d = hypot(v.x - clampedX, v.y - activationRefY)
        chainView.setEngaged(d < CGFloat(style.activationRadius))

        // Is the cursor over the (visible) bead?
        let bead = chainView.beadPosition
        let overBead = chainView.emergenceValue > 0.5
            && hypot(v.x - bead.x, v.y - bead.y) <= CGFloat(style.grabRadius) + 6

        // Interactive while over the bead OR mid-pull; click-through otherwise.
        let grabbed = chainView.isGrabbed
        let wantInteractive = overBead || grabbed
        if wantInteractive != interactive {
            interactive = wantInteractive
            window.ignoresMouseEvents = !wantInteractive
        }

        // Hand cursor only over the pull; reset once when leaving so it never
        // sticks over the background (which owns its own cursor when clicked-through).
        if grabbed {
            NSCursor.closedHand.set(); showingHand = true
        } else if overBead {
            NSCursor.openHand.set(); showingHand = true
        } else if showingHand {
            NSCursor.arrow.set(); showingHand = false
        }
    }

    /// Exposed for tests: true when the overlay currently captures clicks.
    var isInteractive: Bool { !window.ignoresMouseEvents }

    /// Bead position in global screen coords (for hit-testing a grab).
    func beadGlobalPosition() -> CGPoint {
        let b = chainView.beadPosition
        return CGPoint(x: b.x + window.frame.minX, y: b.y + window.frame.minY)
    }

    @discardableResult
    func tryGrab(globalPoint p: CGPoint) -> Bool { chainView.tryGrab(at: toView(p)) }

    func drag(globalPoint p: CGPoint) { chainView.drag(to: toView(p)) }

    @discardableResult
    func release() -> Bool { chainView.release() }

    var isGrabbed: Bool { chainView.isGrabbed }

    // MARK: - Notch hot zone (for the right-click menu + cursor hint)

    func notchHotZone() -> CGRect { geometry.notchRect.insetBy(dx: -14, dy: -12) }
    func isInNotchHotZone(globalPoint p: CGPoint) -> Bool { notchHotZone().contains(p) }

    // MARK: - Geometry

    static func computeGeometry(for screen: NSScreen) -> NotchGeometry {
        NotchGeometry.compute(screenFrame: screen.frame,
                              safeAreaTop: screen.safeAreaInsets.top,
                              auxLeft: screen.auxiliaryTopLeftArea,
                              auxRight: screen.auxiliaryTopRightArea)
    }

    static func windowFrame(for screen: NSScreen, geometry: NotchGeometry) -> NSRect {
        let f = screen.frame
        let width = min(f.width, geometry.notchRect.width + 520)
        let height: CGFloat = 360
        var x = geometry.shoulder.x - width / 2
        x = max(f.minX, min(x, f.maxX - width))
        let y = f.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
