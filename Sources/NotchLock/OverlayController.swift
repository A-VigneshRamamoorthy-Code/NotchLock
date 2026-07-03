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

    /// Whether the overlay is currently interactive (only after the dwell).
    private var interactive = false
    /// Whether we're currently showing a hand cursor (so we can reset it).
    private var showingHand = false
    /// When the cursor first came to rest over the bead (for the grab dwell).
    private var beadHoverSince: CFTimeInterval?
    /// Fires after the dwell to flip interactive even if the cursor is still.
    private var dwellTimer: DispatchWorkItem?
    /// How long the cursor must hover the bead before it can grab. Clicks that
    /// happen within this window fall through to whatever is underneath, so the
    /// cord swinging under a cursor (or the cursor brushing past) never eats a
    /// click meant for the background.
    private let grabDwell: CFTimeInterval = 0.18

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

    /// Update engagement + the drop position from the cursor's location. The
    /// overlay only becomes interactive (and shows the hand) after the cursor has
    /// **hovered the bead continuously for `grabDwell`** — so a click that lands
    /// before that still reaches the background. Everywhere else stays fully
    /// click-through.
    func handleMouseMoved(globalPoint p: CGPoint) {
        let v = toView(p)
        chainView.cursorXView = v.x           // drop the cord in line with the pointer
        let clampedX = min(max(v.x, notchMinX), notchMaxX)
        let d = hypot(v.x - clampedX, v.y - activationRefY)
        chainView.setEngaged(d < CGFloat(style.activationRadius))

        // While pulling, always interactive (and closed hand).
        if chainView.isGrabbed {
            setInteractive(true)
            NSCursor.closedHand.set(); showingHand = true
            return
        }

        let overBead = isOverBead(viewPoint: v)
        let now = CFAbsoluteTimeGetCurrent()
        if overBead {
            if beadHoverSince == nil {
                beadHoverSince = now
                scheduleDwell()               // covers the stationary-cursor case
            }
            if now - (beadHoverSince ?? now) >= grabDwell {
                setInteractive(true)
                NSCursor.openHand.set(); showingHand = true
            }
            // else: still within the dwell window → stay click-through.
        } else {
            resetHover()
        }
    }

    private func isOverBead(viewPoint v: CGPoint) -> Bool {
        guard chainView.emergenceValue > 0.5 else { return false }
        let bead = chainView.beadPosition
        return hypot(v.x - bead.x, v.y - bead.y) <= CGFloat(style.grabRadius) + 6
    }

    /// Recomputes over-the-bead from the *live* cursor position (used by the dwell
    /// timer, since the bead may have moved while the cursor stayed still).
    private func cursorIsOverBead() -> Bool {
        isOverBead(viewPoint: toView(NSEvent.mouseLocation))
    }

    private func scheduleDwell() {
        dwellTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.chainView.isGrabbed, self.cursorIsOverBead() else { return }
            self.setInteractive(true)
            NSCursor.openHand.set(); self.showingHand = true
        }
        dwellTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + grabDwell + 0.01, execute: work)
    }

    private func resetHover() {
        beadHoverSince = nil
        dwellTimer?.cancel(); dwellTimer = nil
        setInteractive(false)
        if showingHand { NSCursor.arrow.set(); showingHand = false }
    }

    private func setInteractive(_ value: Bool) {
        guard value != interactive else { return }
        interactive = value
        window.ignoresMouseEvents = !value
    }

    /// True only once the grab dwell has elapsed — the app gates grabs on this so
    /// an immediate click over a just-arrived bead goes to the background instead.
    var readyToGrab: Bool { interactive }

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
