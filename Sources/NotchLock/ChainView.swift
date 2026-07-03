import AppKit
import QuartzCore
import NotchLockCore

/// Draws the pull-cord via the engine each frame. The display link runs only
/// while the cord is moving or being held; once it settles (hanging still, or
/// tucked away) the link pauses, dropping CPU to ~0. The last frame stays on
/// screen while paused, so a still cord remains visible. Only the cord's
/// bounding box is invalidated each frame.
final class ChainView: NSView {
    private(set) var engine: ChainEngine
    var style: ChainStyle {
        didSet { engine.style = style }
    }
    private(set) var engaged = false

    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var lastDirty: CGRect = .null

    init(frame: NSRect, shoulder: CGPoint, style: ChainStyle) {
        self.style = style
        self.engine = ChainEngine(shoulder: shoulder, style: style)
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

    /// Update engagement. Resumes the loop when entering/leaving the zone or when
    /// moving within it (so grabbing stays responsive); a still, disengaged cord
    /// stays paused → 0% CPU.
    func setEngaged(_ value: Bool) {
        let changed = value != engaged
        engaged = value
        if value || changed { resume() }
    }

    // MARK: - Interaction (coords are in this view's space)

    var beadPosition: CGPoint { engine.beadPosition }

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
