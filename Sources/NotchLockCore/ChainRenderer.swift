import CoreGraphics
import Foundation

/// Draws the pull-cord + handle into a Core Graphics context. CoreGraphics-only
/// so it renders both on screen and into offscreen bitmaps for previews/tests.
/// Expects a bottom-left origin. The look is chosen by `style.look`.
public enum ChainRenderer {
    public static func draw(in ctx: CGContext, state: ChainState, style: ChainStyle) {
        let em = Double(state.emergence)
        guard em > 0.004 else { return }
        let dense = smooth(state.nodes, samplesPerSeg: 6)
        guard dense.count >= 2 else { return }

        switch style.look {
        case .brass:     drawBrass(ctx, dense: dense, state: state, style: style, em: em)
        case .rope:      drawRope(ctx, dense: dense, state: state, style: style, em: em)
        case .ballChain: drawBallChain(ctx, dense: dense, state: state, style: style, em: em)
        case .neon:      drawNeon(ctx, dense: dense, state: state, style: style, em: em)
        }
    }

    /// Padded bounding box of the cord — lets the view invalidate just the dirty
    /// region each frame (generous to cover handles + neon glow).
    public static func bounds(of state: ChainState, style: ChainStyle) -> CGRect {
        var minX = Double.greatestFiniteMagnitude, minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
        for node in state.nodes {
            minX = min(minX, Double(node.x)); maxX = max(maxX, Double(node.x))
            minY = min(minY, Double(node.y)); maxY = max(maxY, Double(node.y))
        }
        let pad = style.beadRadius * 2.4 + style.cordBaseWidth + 18
        return CGRect(x: minX - pad, y: minY - pad,
                      width: (maxX - minX) + pad * 2, height: (maxY - minY) + pad * 2)
    }

    // MARK: - Brass bead

    private static func drawBrass(_ ctx: CGContext, dense: [CGPoint], state: ChainState,
                                  style: ChainStyle, em: Double) {
        let cordColor = state.armed ? style.armed : style.cord
        let widths = linearWidths(dense.count, baseW: style.cordBaseWidth, tipW: style.cordTipWidth)
        fillRibbon(ctx, points: dense, widths: widths.map { $0 + 2.4 }, color: style.outline.cg(em * 0.55))
        fillRibbon(ctx, points: dense, widths: widths, color: cordColor.cg(em))
        fillRibbon(ctx, points: dense, widths: widths.map { max(0.6, $0 * 0.34) },
                   color: style.cordHighlight.cg(em * 0.7))
        drawRoundBead(ctx, at: state.tip, r: style.beadRadius,
                      body: state.armed ? style.armed : style.bead,
                      highlight: state.armed ? RGBA(1.0, 0.78, 0.72) : style.beadHighlight,
                      outline: style.outline, armed: state.armed, armedColor: style.armed, alpha: em)
    }

    // MARK: - Thick rope + wooden ring

    private static func drawRope(_ ctx: CGContext, dense: [CGPoint], state: ChainState,
                                 style: ChainStyle, em: Double) {
        let cordColor = state.armed ? style.armed : style.cord
        let widths = linearWidths(dense.count, baseW: style.cordBaseWidth, tipW: style.cordTipWidth)
        // Dark casing, jute body, then twisted-fibre bands + a soft centre sheen.
        fillRibbon(ctx, points: dense, widths: widths.map { $0 + 3.0 }, color: style.outline.cg(em * 0.7))
        fillRibbon(ctx, points: dense, widths: widths, color: cordColor.cg(em))
        drawTwist(ctx, points: dense, widths: widths, color: style.outline.cg(em * 0.35), em: em)
        fillRibbon(ctx, points: dense, widths: widths.map { max(0.8, $0 * 0.30) },
                   color: style.cordHighlight.cg(em * 0.5))

        // Wooden ring hung at the very end (cord attaches at its top).
        let tip = state.tip
        let prev = dense[max(0, dense.count - 2)]
        var dx = Double(tip.x - prev.x), dy = Double(tip.y - prev.y)
        let dl = max(1e-4, (dx * dx + dy * dy).squareRoot()); dx /= dl; dy /= dl
        let outerR = style.beadRadius, innerR = style.beadRadius * 0.52
        let center = CGPoint(x: Double(tip.x) + dx * outerR, y: Double(tip.y) + dy * outerR)
        let ringColor = state.armed ? style.armed : style.bead
        drawWoodRing(ctx, center: center, outerR: outerR, innerR: innerR,
                     body: ringColor, highlight: style.beadHighlight,
                     outline: style.outline, alpha: em)
    }

    private static func drawWoodRing(_ ctx: CGContext, center: CGPoint, outerR: Double, innerR: Double,
                                     body: RGBA, highlight: RGBA, outline: RGBA, alpha: Double) {
        let cx = Double(center.x), cy = Double(center.y)
        func ellipse(_ r: Double) -> CGRect { CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2) }
        // Outline annulus.
        let oline = CGMutablePath()
        oline.addEllipse(in: ellipse(outerR + 1.4)); oline.addEllipse(in: ellipse(innerR - 0.6))
        ctx.addPath(oline); ctx.setFillColor(outline.cg(alpha * 0.65)); ctx.fillPath(using: .evenOdd)
        // Wood annulus.
        let ring = CGMutablePath()
        ring.addEllipse(in: ellipse(outerR)); ring.addEllipse(in: ellipse(innerR))
        ctx.addPath(ring); ctx.setFillColor(body.cg(alpha)); ctx.fillPath(using: .evenOdd)
        // Top highlight arc (thin, upper-left).
        ctx.saveGState()
        ctx.setStrokeColor(highlight.cg(alpha * 0.8))
        ctx.setLineWidth((outerR - innerR) * 0.42)
        ctx.setLineCap(.round)
        let midR = (outerR + innerR) / 2
        ctx.addArc(center: center, radius: CGFloat(midR), startAngle: .pi * 0.45, endAngle: .pi * 1.05, clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Ball chain

    private static func drawBallChain(_ ctx: CGContext, dense: [CGPoint], state: ChainState,
                                      style: ChainStyle, em: Double) {
        let color = state.armed ? style.armed : style.bead
        let hi = state.armed ? RGBA(1.0, 0.82, 0.78) : style.beadHighlight
        let r = 3.6                                   // little chain beads
        let spacing = r * 2.05
        // Walk arc-length and drop a bead every `spacing`.
        var acc = 0.0
        var beads: [CGPoint] = [dense[0]]
        for i in 1..<dense.count {
            let d = hypot(Double(dense[i].x - dense[i - 1].x), Double(dense[i].y - dense[i - 1].y))
            acc += d
            if acc >= spacing { acc = 0; beads.append(dense[i]) }
        }
        // Draw each little bead (outline dot + body + speckle highlight).
        for (idx, p) in beads.enumerated() {
            let t = Double(idx) / Double(max(1, beads.count - 1))
            let rr = r * (1.0 - 0.12 * t)
            ctx.setFillColor(style.outline.cg(em * 0.5))
            ctx.fillEllipse(in: CGRect(x: Double(p.x) - rr - 0.8, y: Double(p.y) - rr - 0.8,
                                       width: (rr + 0.8) * 2, height: (rr + 0.8) * 2))
            ctx.setFillColor(color.cg(em))
            ctx.fillEllipse(in: CGRect(x: Double(p.x) - rr, y: Double(p.y) - rr, width: rr * 2, height: rr * 2))
            ctx.setFillColor(hi.cg(em * 0.85))
            ctx.fillEllipse(in: CGRect(x: Double(p.x) - rr * 0.35, y: Double(p.y) + rr * 0.15,
                                       width: rr * 0.6, height: rr * 0.6))
        }
        // End knob (the grabbable pull) at the tip.
        drawRoundBead(ctx, at: state.tip, r: style.beadRadius, body: color, highlight: hi,
                      outline: style.outline, armed: state.armed, armedColor: style.armed, alpha: em)
    }

    // MARK: - Neon cord

    private static func drawNeon(_ ctx: CGContext, dense: [CGPoint], state: ChainState,
                                 style: ChainStyle, em: Double) {
        let glow = state.armed ? style.armed : style.cord
        let widths = linearWidths(dense.count, baseW: style.cordBaseWidth, tipW: style.cordTipWidth)
        // Wide soft halo (blurred) → tight bright core.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 14, color: glow.cg(em * 0.9))
        fillRibbon(ctx, points: dense, widths: widths.map { $0 + 1.5 }, color: glow.cg(em * 0.9))
        ctx.restoreGState()
        fillRibbon(ctx, points: dense, widths: widths.map { max(0.8, $0 * 0.5) },
                   color: style.cordHighlight.cg(em))
        // Glowing orb.
        drawNeonOrb(ctx, at: state.tip, r: style.beadRadius,
                    body: state.armed ? style.armed : style.bead,
                    highlight: style.beadHighlight, alpha: em)
    }

    private static func drawNeonOrb(_ ctx: CGContext, at p: CGPoint, r: Double,
                                    body: RGBA, highlight: RGBA, alpha: Double) {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: CGFloat(r * 1.8), color: body.cg(alpha))
        ctx.setFillColor(body.cg(alpha))
        ctx.fillEllipse(in: CGRect(x: Double(p.x) - r, y: Double(p.y) - r, width: r * 2, height: r * 2))
        ctx.restoreGState()
        ctx.setFillColor(body.cg(alpha))
        ctx.fillEllipse(in: CGRect(x: Double(p.x) - r, y: Double(p.y) - r, width: r * 2, height: r * 2))
        ctx.setFillColor(highlight.cg(alpha))
        let hr = r * 0.5
        ctx.fillEllipse(in: CGRect(x: Double(p.x) - hr / 2, y: Double(p.y) - hr / 2, width: hr, height: hr))
    }

    // MARK: - Shared bead

    private static func drawRoundBead(_ ctx: CGContext, at p: CGPoint, r: Double, body: RGBA,
                                      highlight: RGBA, outline: RGBA, armed: Bool, armedColor: RGBA, alpha: Double) {
        if armed {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: CGFloat(r * 1.4), color: armedColor.cg(0.9 * alpha))
            ctx.setFillColor(body.cg(alpha))
            ctx.fillEllipse(in: CGRect(x: Double(p.x) - r, y: Double(p.y) - r, width: r * 2, height: r * 2))
            ctx.restoreGState()
        }
        ctx.setFillColor(outline.cg(alpha * 0.6))
        ctx.fillEllipse(in: CGRect(x: Double(p.x) - r - 1.4, y: Double(p.y) - r - 1.4,
                                   width: (r + 1.4) * 2, height: (r + 1.4) * 2))
        ctx.setFillColor(body.cg(alpha))
        ctx.fillEllipse(in: CGRect(x: Double(p.x) - r, y: Double(p.y) - r, width: r * 2, height: r * 2))
        let hr = r * 0.5
        ctx.setFillColor(highlight.cg(alpha * 0.9))
        ctx.fillEllipse(in: CGRect(x: Double(p.x) - r * 0.42 - hr / 2, y: Double(p.y) + r * 0.30 - hr / 2,
                                   width: hr, height: hr))
    }

    // MARK: - Menu / preview icon

    private static var iconCache: [String: CGImage] = [:]

    /// A small hanging cord + handle in the given look. `size` in points.
    public static func icon(for style: ChainStyle, size: CGSize, scale: CGFloat = 2) -> CGImage? {
        let key = "\(style.id)-\(Int(size.width))x\(Int(size.height))"
        if let img = iconCache[key] { return img }
        let px = Int(size.width * scale), py = Int(size.height * scale)
        guard px > 0, py > 0,
              let ctx = CGContext(data: nil, width: px, height: py, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let w = Double(size.width), h = Double(size.height), cx = w / 2

        // A tiny hanging cord + handle, sized to the icon.
        let bead = style.beadRadius * (min(w, h) / 46.0)
        let handleY = h * 0.34
        let nodes = [CGPoint(x: cx, y: h - 1),
                     CGPoint(x: cx + w * 0.02, y: (h + handleY) / 2),
                     CGPoint(x: cx, y: handleY + bead * 0.8)]
        let dense = smooth(nodes, samplesPerSeg: 8)
        let baseW = style.cordBaseWidth * (min(w, h) / 46.0)
        let tipW = style.cordTipWidth * (min(w, h) / 46.0)
        let widths = linearWidths(dense.count, baseW: baseW, tipW: tipW)
        let beadPt = CGPoint(x: cx, y: handleY)

        switch style.look {
        case .brass:
            fillRibbon(ctx, points: dense, widths: widths, color: style.cord.cg(1))
            drawRoundBead(ctx, at: beadPt, r: bead, body: style.bead, highlight: style.beadHighlight,
                          outline: style.outline, armed: false, armedColor: style.armed, alpha: 1)
        case .rope:
            fillRibbon(ctx, points: dense, widths: widths, color: style.cord.cg(1))
            drawTwist(ctx, points: dense, widths: widths, color: style.outline.cg(0.35), em: 1)
            drawWoodRing(ctx, center: CGPoint(x: cx, y: handleY - bead * 0.4), outerR: bead, innerR: bead * 0.52,
                         body: style.bead, highlight: style.beadHighlight, outline: style.outline, alpha: 1)
        case .ballChain:
            drawBallChainPath(ctx, dense: dense, style: style, tip: beadPt, em: 1)
        case .neon:
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 8, color: style.cord.cg(0.9))
            fillRibbon(ctx, points: dense, widths: widths, color: style.cord.cg(0.95))
            ctx.restoreGState()
            drawNeonOrb(ctx, at: beadPt, r: bead, body: style.bead, highlight: style.beadHighlight, alpha: 1)
        }

        let img = ctx.makeImage()
        iconCache[key] = img
        return img
    }

    /// Ball-chain drawing shared between the live view and the menu icon.
    private static func drawBallChainPath(_ ctx: CGContext, dense: [CGPoint], style: ChainStyle,
                                          tip: CGPoint, em: Double) {
        let color = style.bead, hi = style.beadHighlight
        let r = max(2.2, style.beadRadius * 0.30)
        let spacing = r * 2.05
        var acc = 0.0, beads: [CGPoint] = [dense[0]]
        for i in 1..<dense.count {
            acc += hypot(Double(dense[i].x - dense[i - 1].x), Double(dense[i].y - dense[i - 1].y))
            if acc >= spacing { acc = 0; beads.append(dense[i]) }
        }
        for p in beads {
            ctx.setFillColor(color.cg(em))
            ctx.fillEllipse(in: CGRect(x: Double(p.x) - r, y: Double(p.y) - r, width: r * 2, height: r * 2))
            ctx.setFillColor(hi.cg(em * 0.8))
            ctx.fillEllipse(in: CGRect(x: Double(p.x) - r * 0.35, y: Double(p.y) + r * 0.15, width: r * 0.6, height: r * 0.6))
        }
        drawRoundBead(ctx, at: tip, r: style.beadRadius, body: color, highlight: hi,
                      outline: style.outline, armed: false, armedColor: style.armed, alpha: em)
    }

    // MARK: - App icon (kept: brass keyholed bead dropping from the notch)

    public static func appIcon(pt: CGFloat = 1024, scale: CGFloat = 1) -> CGImage? {
        let px = Int(pt * scale)
        guard px > 0,
              let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let n = Double(pt)
        let margin = n * 0.085
        let plate = CGRect(x: margin, y: margin, width: n - margin * 2, height: n - margin * 2)
        let radius = plate.width * 0.225
        let platePath = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.addPath(platePath); ctx.clip()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let top = CGColor(srgbRed: 0.16, green: 0.20, blue: 0.42, alpha: 1)
        let bottom = CGColor(srgbRed: 0.07, green: 0.08, blue: 0.16, alpha: 1)
        if let grad = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: plate.maxY),
                                   end: CGPoint(x: 0, y: plate.minY), options: [])
        }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.06))
        ctx.fillEllipse(in: CGRect(x: plate.minX - plate.width * 0.1, y: plate.midY,
                                   width: plate.width * 1.2, height: plate.height * 0.8))
        ctx.restoreGState()

        let style = ChainStyle.standard
        let cx = n / 2
        let nubW = n * 0.30, nubH = n * 0.075
        let nub = CGRect(x: cx - nubW / 2, y: plate.maxY - nubH * 1.15, width: nubW, height: nubH)
        ctx.setFillColor(CGColor(srgbRed: 0.02, green: 0.02, blue: 0.05, alpha: 1))
        ctx.addPath(CGPath(roundedRect: nub, cornerWidth: nubH * 0.4, cornerHeight: nubH * 0.4, transform: nil))
        ctx.fillPath()

        let beadY = n * 0.40
        let beadR = n * 0.135
        let cordPts = [CGPoint(x: cx, y: nub.minY + nubH * 0.2),
                       CGPoint(x: cx + n * 0.02, y: (nub.minY + beadY) / 2),
                       CGPoint(x: cx, y: beadY + beadR * 0.7)]
        let dense = smooth(cordPts, samplesPerSeg: 10)
        let widths = linearWidths(dense.count, baseW: n * 0.028, tipW: n * 0.020)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -n * 0.008), blur: n * 0.02,
                      color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
        fillRibbon(ctx, points: dense, widths: widths, color: style.cord.cg(1))
        let bead = CGPoint(x: cx, y: beadY)
        if let grad = CGGradient(colorsSpace: space,
                                 colors: [style.beadHighlight.cg(1), style.bead.cg(1),
                                          CGColor(srgbRed: 0.55, green: 0.42, blue: 0.16, alpha: 1)] as CFArray,
                                 locations: [0, 0.5, 1]) {
            ctx.saveGState()
            ctx.addPath(CGPath(ellipseIn: CGRect(x: Double(bead.x) - beadR, y: Double(bead.y) - beadR,
                                                 width: beadR * 2, height: beadR * 2), transform: nil))
            ctx.clip()
            ctx.drawRadialGradient(grad,
                                   startCenter: CGPoint(x: bead.x - beadR * 0.35, y: bead.y + beadR * 0.35),
                                   startRadius: 0, endCenter: bead, endRadius: beadR * 1.15, options: [])
            ctx.restoreGState()
        }
        ctx.restoreGState()
        ctx.setFillColor(CGColor(srgbRed: 0.10, green: 0.08, blue: 0.03, alpha: 1))
        let khR = beadR * 0.28
        ctx.fillEllipse(in: CGRect(x: Double(bead.x) - khR, y: Double(bead.y) - khR * 0.2,
                                   width: khR * 2, height: khR * 2))
        ctx.beginPath()
        ctx.move(to: CGPoint(x: bead.x - khR * 0.5, y: bead.y))
        ctx.addLine(to: CGPoint(x: bead.x + khR * 0.5, y: bead.y))
        ctx.addLine(to: CGPoint(x: bead.x + khR * 0.9, y: bead.y - beadR * 0.62))
        ctx.addLine(to: CGPoint(x: bead.x - khR * 0.9, y: bead.y - beadR * 0.62))
        ctx.closePath()
        ctx.fillPath()
        return ctx.makeImage()
    }

    // MARK: - Ribbon + twist + smoothing

    private static func linearWidths(_ n: Int, baseW: Double, tipW: Double) -> [Double] {
        guard n > 1 else { return [baseW] }
        return (0..<n).map { baseW + (tipW - baseW) * Double($0) / Double(n - 1) }
    }

    /// Short diagonal darker bands across a thick cord → twisted-fibre texture.
    private static func drawTwist(_ ctx: CGContext, points: [CGPoint], widths: [Double], color: CGColor, em: Double) {
        let n = points.count
        guard n >= 3 else { return }
        ctx.saveGState()
        ctx.setStrokeColor(color)
        ctx.setLineCap(.round)
        let stride = 5
        var i = 2
        while i < n - 1 {
            let prev = points[i - 1], next = points[i + 1]
            var tx = Double(next.x - prev.x), ty = Double(next.y - prev.y)
            let tl = max(1e-4, (tx * tx + ty * ty).squareRoot()); tx /= tl; ty /= tl
            let nx = -ty, ny = tx
            let w = widths[i] * 0.5
            // Skew the band along the tangent to imply a spiral twist.
            let a = CGPoint(x: Double(points[i].x) + nx * w - tx * w * 0.9,
                            y: Double(points[i].y) + ny * w - ty * w * 0.9)
            let b = CGPoint(x: Double(points[i].x) - nx * w + tx * w * 0.9,
                            y: Double(points[i].y) - ny * w + ty * w * 0.9)
            ctx.setLineWidth(max(0.8, widths[i] * 0.18))
            ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
            i += stride
        }
        ctx.restoreGState()
    }

    private static func fillRibbon(_ ctx: CGContext, points: [CGPoint], widths: [Double], color: CGColor) {
        let n = points.count
        guard n >= 2, widths.count == n else { return }
        var left = [CGPoint](), right = [CGPoint]()
        left.reserveCapacity(n); right.reserveCapacity(n)
        for i in 0..<n {
            let prev = points[max(0, i - 1)]
            let next = points[min(n - 1, i + 1)]
            var tx = Double(next.x - prev.x), ty = Double(next.y - prev.y)
            let tl = max(1e-4, (tx * tx + ty * ty).squareRoot())
            tx /= tl; ty /= tl
            let nx = -ty, ny = tx
            let w = widths[i] * 0.5
            left.append(CGPoint(x: Double(points[i].x) + nx * w, y: Double(points[i].y) + ny * w))
            right.append(CGPoint(x: Double(points[i].x) - nx * w, y: Double(points[i].y) - ny * w))
        }
        ctx.beginPath()
        addSmoothBoundary(ctx, left, startsPath: true)
        let tip = points[n - 1]
        ctx.addArc(center: tip, radius: max(0.5, widths[n - 1] * 0.5),
                   startAngle: 0, endAngle: .pi, clockwise: false)
        addSmoothBoundary(ctx, Array(right.reversed()), startsPath: false)
        ctx.closePath()
        ctx.setFillColor(color)
        ctx.fillPath()
    }

    private static func addSmoothBoundary(_ ctx: CGContext, _ pts: [CGPoint], startsPath: Bool) {
        guard let first = pts.first else { return }
        if startsPath { ctx.move(to: first) } else { ctx.addLine(to: first) }
        if pts.count < 3 {
            for p in pts.dropFirst() { ctx.addLine(to: p) }
            return
        }
        for i in 1..<(pts.count - 1) {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) * 0.5,
                              y: (pts[i].y + pts[i + 1].y) * 0.5)
            ctx.addQuadCurve(to: mid, control: pts[i])
        }
        ctx.addLine(to: pts[pts.count - 1])
    }

    private static func smooth(_ pts: [CGPoint], samplesPerSeg: Int) -> [CGPoint] {
        guard pts.count >= 3 else { return pts }
        let n = pts.count
        var out = [CGPoint]()
        out.reserveCapacity(n * samplesPerSeg)
        for i in 0..<(n - 1) {
            let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(n - 1, i + 2)]
            for sIdx in 0..<samplesPerSeg {
                let t = Double(sIdx) / Double(samplesPerSeg)
                out.append(catmull(p0, p1, p2, p3, t))
            }
        }
        out.append(pts[n - 1])
        return out
    }

    private static func catmull(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: Double) -> CGPoint {
        let t2 = t * t, t3 = t2 * t
        func c(_ a: CGFloat, _ b: CGFloat, _ cc: CGFloat, _ d: CGFloat) -> CGFloat {
            CGFloat(0.5 * (2 * Double(b) + (Double(cc) - Double(a)) * t
                + (2 * Double(a) - 5 * Double(b) + 4 * Double(cc) - Double(d)) * t2
                + (-Double(a) + 3 * Double(b) - 3 * Double(cc) + Double(d)) * t3))
        }
        return CGPoint(x: c(p0.x, p1.x, p2.x, p3.x), y: c(p0.y, p1.y, p2.y, p3.y))
    }
}

extension RGBA {
    /// Convert to a Core Graphics colour, multiplying alpha by `alpha`.
    public func cg(_ alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a * alpha)
    }
}
