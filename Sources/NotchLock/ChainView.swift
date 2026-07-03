import AppKit
import QuartzCore
import NotchLockCore

/// Draws the pull-cord via the engine each frame. The display link runs only
/// while the cord is moving or being held; once it settles (hanging still, or
/// tucked away) the link pauses, dropping CPU to ~0.
///
/// Two behaviours live here beyond drawing:
///  • The anchor (where the cord drops from) slides along the notch to sit under
///    the cursor's x, so the string appears in line with the pointer — not always
///    centred. It freezes while the cord is held.
///  • Only the small, moving bead is interactive (`hitTest`), so the hand cursor
///    shows on hover / closed-hand while pulling, while every other click passes
///    straight through the overlay.
final class ChainView: NSView {
    private(set) var engine: ChainEngine
    var style: ChainStyle {
        didSet { engine.style = style }
    }
    private(set) var engaged = false

    // Notch span the anchor may slide along + the anchor's fixed y (view coords).
    private let notchMinX: CGFloat
    private let notchMaxX: CGFloat
    private let shoulderY: CGFloat
    private var shoulderX: CGFloat
    /// Latest cursor x in view coords — drives where the cord drops from.
    var cursorXView: CGFloat

    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var lastDirty: CGRect = .null

    init(frame: NSRect, notchMinX: CGFloat, notchMaxX: CGFloat, shoulderY: CGFloat, style: ChainStyle) {
        self.style = style
        self.notchMinX = notchMinX
        self.notchMaxX = notchMaxX
        self.shoulderY = shoulderY
        let midX = (notchMinX + notchMaxX) / 2
        self.shoulderX = midX
        self.cursorXView = midX
        self.engine = ChainEngine(shoulder: CGPoint(x: midX, y: shoulderY), style: style)
        super.init(frame: frame)
        clipsToBounds = true   // clip the cord flush at the top edge / into the notch
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, link == nil {
            let l = displayLink(target: self, selector: #selector(tick(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
            l.add(to: .main, forMode: .common)
            l.isPaused = true
            link = l
        }
    }

    func resume() {
        guard let link else { return }
        if link.isPaused {
            lastTime = 0
            link.isPaused = false
        }
    }

    func setEngaged(_ value: Bool) {
        let changed = value != engaged
        engaged = value
        if value || changed { resume() }
    }

    // MARK: - Interaction (coords are in this view's space)

    var beadPosition: CGPoint { engine.beadPosition }
    var emergenceValue: Double { engine.emergenceValue }

    @discardableResult
    func tryGrab(at p: CGPoint) -> Bool {
        resume()
        return engine.grab(at: p)
    }

    func drag(to p: CGPoint) {
        engine.drag(to: p)
        resume()
    }

    /// Returns whether the pull passed the arming threshold (⇒ lock the screen).
    @discardableResult
    func release() -> Bool {
        let fired = engine.release()
        resume()
        return fired
    }

    var isGrabbed: Bool { engine.isGrabbed }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTime > 0 ? now - lastTime : 1.0 / 60.0
        lastTime = now

        // Anchor the cord to the notch point nearest the cursor's x, so it drops
        // in line with the pointer. Snap before it emerges (so it appears under
        // the cursor), ease afterwards, and freeze while the user holds it.
        if !engine.isGrabbed {
            let desired = min(max(cursorXView, notchMinX), notchMaxX)
            if engine.emergenceValue < 0.05 {
                shoulderX = desired
            } else {
                shoulderX += (desired - shoulderX) * min(1, CGFloat(dt) * 11)
            }
            engine.shoulder = CGPoint(x: shoulderX, y: shoulderY)
        }

        engine.update(dt: dt, engaged: engaged)
        let current = ChainRenderer.bounds(of: engine.state, style: style)
        setNeedsDisplay(current.union(lastDirty))
        lastDirty = current

        if !engine.isGrabbed && engine.isMotionless {
            link.isPaused = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(dirtyRect)
        ChainRenderer.draw(in: ctx, state: engine.state, style: style)
    }
}
