import CoreGraphics
import Foundation

/// Draws the pull-cord (a tapered brass ribbon) and its round bead into a Core
/// Graphics context. CoreGraphics-only so it renders both on screen and into
/// offscreen bitmaps for previews/tests. Expects a bottom-left origin.
public enum ChainRenderer {
    public static func draw(in ctx: CGContext, state: ChainState, style: ChainStyle) {
        let em = Double(state.emergence)
        guard em > 0.004 else { return }

        let dense = smooth(state.nodes, samplesPerSeg: 6)
        let n = dense.count
        guard n >= 2 else { return }

        let cordColor = state.armed ? style.armed : style.cord
        let baseW = style.cordBaseWidth, tipW = style.cordTipWidth
        let widths = linearWidths(n, baseW: baseW, tipW: tipW)

        // Soft outline pass, then the cord fill, then a thin top highlight.
        fillRibbon(ctx, points: dense, widths: widths.map { $0 + 2.4 }, color: style.outline.cg(em * 0.55))
        fillRibbon(ctx, points: dense, widths: widths, color: cordColor.cg(em))
        fillRibbon(ctx, points: dense, widths: widths.map { max(0.6, $0 * 0.34) },
                   color: style.cordHighlight.cg(em * 0.7))

        // Bead / pull-knob at the tip.
        drawBead(ctx, at: state.tip, style: style, armed: state.armed, alpha: em)
    }

    /// Padded bounding box of the cord — lets the view invalidate just the dirty
    /// region each frame.
    public static func bounds(of state: ChainState, style: ChainStyle) -> CGRect {
        var minX = Double.greatestFiniteMagnitude, minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
        for node in state.nodes {
            minX = min(minX, Double(node.x)); maxX = max(maxX, Double(node.x))
            minY = min(minY, Double(node.y)); maxY = max(maxY, Double(node.y))
        }
        let pad = style.beadRadius + style.cordBaseWidth + 12
        return CGRect(x: minX - pad, y: minY - pad,
                      width: (maxX - minX) + pad * 2, height: (maxY - minY) + pad * 2)
    }

    // MARK: - Bead

    private static func drawBead(_ ctx: CGContext, at p: CGPoint, style: ChainStyle,
                                 armed: Bool, alpha: Double) {
        let r = style.beadRadius
        let body = armed ? style.armed : style.bead
        let hi = armed ? RGBA(1.0, 0.78, 0.72) : style.beadHighlight

        // Armed glow.
        if armed {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: CGFloat(r * 1.4),
                          color: style.armed.cg(0.9 * alpha))
            ctx.setFillColor(body.cg(alpha))
            ctx.fillEllipse(in: CGRect(x: Double(p.x) - r, y: Double(p.y) - r, width: r * 2, height: r * 2))
            ctx.restoreGState()
        }

        // Outline + body.
        ctx.setFillColor(style.outline.cg(alpha * 0.6))
        ctx.fillEllipse(in: CGRect(x: Double(p.x) - r - 1.4, y: Double(p.y) - r - 1.4,
                                   width: (r + 1.4) * 2, height: (r + 1.4) * 2))
        ctx.setFillColor(body.cg(alpha))
        ctx.fillEllipse(in: CGRect(x: Double(p.x) - r, y: Double(p.y) - r, width: r * 2, height: r * 2))

        // Top-left specular highlight.
        let hr = r * 0.5
        ctx.setFillColor(hi.cg(alpha * 0.9))
        ctx.fillEllipse(in: CGRect(x: Double(p.x) - r * 0.42 - hr / 2,
                                   y: Double(p.y) + r * 0.30 - hr / 2,
                                   width: hr, height: hr))
    }

    // MARK: - Menu / preview icon

    private static var iconCache: [String: CGImage] = [:]

    /// A small pull-cord + bead icon for menus/previews. `size` in points.
    public static func icon(for style: ChainStyle, size: CGSize, scale: CGFloat = 2) -> CGImage? {
        let key = "cord-\(Int(size.width))x\(Int(size.height))"
        if let img = iconCache[key] { return img }
        let px = Int(size.width * scale), py = Int(size.height * scale)
        guard px > 0, py > 0,
              let ctx = CGContext(data: nil, width: px, height: py, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let w = Double(size.width), h = Double(size.height)
        let cx = w / 2
        let pts = [CGPoint(x: cx, y: h - 2),
                   CGPoint(x: cx + w * 0.02, y: h * 0.62),
                   CGPoint(x: cx, y: h * 0.40)]
        let dense = smooth(pts, samplesPerSeg: 8)
        let widths = linearWidths(dense.count, baseW: min(w, h) * 0.10, tipW: min(w, h) * 0.07)
        fillRibbon(ctx, points: dense, widths: widths, color: style.cord.cg(1))
        let bead = CGPoint(x: cx, y: h * 0.32)
        drawBead(ctx, at: bead, style: style, armed: false, alpha: 1)
        let img = ctx.makeImage()
        iconCache[key] = img
        return img
    }

    // MARK: - App icon

    /// The NotchLock application icon: a pull-cord + keyholed bead dropping from
    /// a notch, on a deep gradient plate. `pt` is the icon edge length in points.
    public static func appIcon(pt: CGFloat = 1024, scale: CGFloat = 1) -> CGImage? {
        let px = Int(pt * scale)
        guard px > 0,
              let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let n = Double(pt)

        // Rounded-square plate with a deep night-blue → indigo gradient (padding
        // so the system squircle mask never clips the art).
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

        // Notch nub near the top of the plate.
        let nubW = n * 0.30, nubH = n * 0.075
        let nub = CGRect(x: cx - nubW / 2, y: plate.maxY - nubH * 1.15, width: nubW, height: nubH)
        ctx.setFillColor(CGColor(srgbRed: 0.02, green: 0.02, blue: 0.05, alpha: 1))
        ctx.addPath(CGPath(roundedRect: nub, cornerWidth: nubH * 0.4, cornerHeight: nubH * 0.4, transform: nil))
        ctx.fillPath()

        // Brass pull-cord dropping from the notch to a big bead.
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

        // Bead with a keyhole → "the pull that locks".
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
                                   startRadius: 0,
                                   endCenter: bead, endRadius: beadR * 1.15, options: [])
            ctx.restoreGState()
        }
        ctx.restoreGState()

        // Keyhole cut into the bead.
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

    // MARK: - Ribbon + smoothing (adapted from the NotchPaw renderer)

    private static func linearWidths(_ n: Int, baseW: Double, tipW: Double) -> [Double] {
        guard n > 1 else { return [baseW] }
        return (0..<n).map { baseW + (tipW - baseW) * Double($0) / Double(n - 1) }
    }

    /// Fill a ribbon whose half-thickness at each point comes from `widths`.
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
