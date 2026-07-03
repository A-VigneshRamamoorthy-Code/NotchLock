import AppKit
import CoreGraphics
import Foundation
import ImageIO
import NotchLockCore
import UniformTypeIdentifiers

/// Renders the cord and animation frames to PNGs for headless visual
/// verification. `--render <dir>` = static poses; `--contact <dir>` = a pull +
/// release + swing contact-sheet; `--appicon <png>` = the app icon.
enum PreviewRenderer {
    private static let cell = CGSize(width: 240, height: 320)

    private static func makeEngine() -> ChainEngine {
        let shoulder = CGPoint(x: cell.width / 2, y: cell.height + 16)
        return ChainEngine(shoulder: shoulder, style: .standard)
    }

    // Static poses: at rest, and armed (pulled past the threshold).
    static func renderAll(to dir: String) {
        ensureDir(dir)

        var rest = makeEngine()
        for _ in 0..<90 { rest.update(dt: 1.0 / 60.0, engaged: true) }
        renderPose(rest, name: "hanging", to: dir)

        var pulled = makeEngine()
        for _ in 0..<40 { pulled.update(dt: 1.0 / 60.0, engaged: true) }
        _ = pulled.grab(at: pulled.beadPosition)
        let downY = pulled.shoulder.y - CGFloat(ChainStyle.standard.restLength + ChainStyle.standard.pullThreshold + 20)
        for _ in 0..<40 {
            pulled.drag(to: CGPoint(x: pulled.shoulder.x + 6, y: downY))
            pulled.update(dt: 1.0 / 60.0, engaged: true)
        }
        renderPose(pulled, name: "armed", to: dir)
    }

    // Animation contact sheet: emerge → grab → pull down → release → swing.
    static func renderContact(to dir: String) {
        ensureDir(dir)
        let cols = 6, rows = 4
        let frames = cols * rows
        let sheet = CGSize(width: cell.width * CGFloat(cols), height: cell.height * CGFloat(rows))
        guard let ctx = makeContext(size: sheet) else { return }

        var engine = makeEngine()
        let s = ChainStyle.standard
        // Warm up: cord drops out of the notch.
        for _ in 0..<30 { engine.update(dt: 1.0 / 60.0, engaged: true) }
        _ = engine.grab(at: engine.beadPosition)

        var step = 0
        let stepsPerFrame = 7        // ~0.117s between captured frames
        let pullSteps = 30           // pulling down
        let releaseStep = 36         // let go
        var released = false
        let pullTargetY = engine.shoulder.y - CGFloat(s.restLength + s.pullThreshold + 26)

        for f in 0..<frames {
            let col = f % cols, row = f / cols
            let ox = CGFloat(col) * cell.width
            let oy = sheet.height - CGFloat(row + 1) * cell.height
            ctx.saveGState()
            ctx.translateBy(x: ox, y: oy)
            drawScene(ctx, engine: engine)
            ctx.restoreGState()

            for _ in 0..<stepsPerFrame {
                if step < pullSteps {
                    let t = CGFloat(step) / CGFloat(pullSteps)
                    let y = engine.shoulder.y - CGFloat(s.restLength) - (engine.shoulder.y - CGFloat(s.restLength) - pullTargetY) * t
                    engine.drag(to: CGPoint(x: engine.shoulder.x + 10 * t, y: y))
                } else if step >= releaseStep && !released {
                    _ = engine.release()
                    released = true
                }
                engine.update(dt: 1.0 / 60.0, engaged: true)
                step += 1
            }
        }
        save(ctx, to: dir, name: "pull-swing")
    }

    static func renderAppIcon(to path: String) -> Bool {
        guard let img = ChainRenderer.appIcon(pt: 1024, scale: 1) else { return false }
        let url = URL(fileURLWithPath: path)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, img, nil)
        let ok = CGImageDestinationFinalize(dest)
        if ok { FileHandle.standardOutput.write("rendered \(url.path)\n".data(using: .utf8)!) }
        return ok
    }

    // A showcase strip of every cord look (hanging), for the README.
    static func renderStyles(to path: String) -> Bool {
        let styles = CordStyle.allCases
        let cw = cell.width, ch = cell.height
        let sheet = CGSize(width: cw * CGFloat(styles.count), height: ch)
        guard let ctx = makeContext(size: sheet) else { return false }
        for (i, s) in styles.enumerated() {
            let shoulder = CGPoint(x: cw / 2, y: ch + 16)
            var e = ChainEngine(shoulder: shoulder, style: s.style)
            // let it drop + sway a touch for character
            for _ in 0..<Int(1.6 * 60) { e.update(dt: 1.0 / 60.0, engaged: true) }
            ctx.saveGState()
            ctx.translateBy(x: CGFloat(i) * cw, y: 0)
            drawScene(ctx, engine: e, label: s.displayName)
            ctx.restoreGState()
        }
        guard let image = ctx.makeImage() else { return false }
        let url = URL(fileURLWithPath: path)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        let ok = CGImageDestinationFinalize(dest)
        if ok { FileHandle.standardOutput.write("rendered \(url.path)\n".data(using: .utf8)!) }
        return ok
    }

    // MARK: - Helpers

    /// Render a faithful mockup of the right-click menu (real MenuHeaderView +
    /// section header + style rows) so the header styling can be eyeballed.
    static func renderMenu(to path: String, dark: Bool) -> Bool {
        let scale: CGFloat = 2
        let W = 300, rowH = 46
        let styles = CordStyle.allCases
        let extras = ["Lock Screen Now", "Launch at Login", "Quit NotchLock"]
        let H = 56 + 10 + 24 + styles.count * rowH + 10 + extras.count * 34 + 24
        guard let ctx = CGContext(data: nil, width: W * Int(scale), height: H * Int(scale),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.scaleBy(x: scale, y: scale)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
        NSAppearance.current = NSAppearance(named: dark ? .darkAqua : .aqua)

        // Menu panel background (rounded, material-ish).
        let bg = dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.97, alpha: 1)
        let panel = NSBezierPath(roundedRect: NSRect(x: 6, y: 6, width: W - 12, height: H - 12),
                                 xRadius: 12, yRadius: 12)
        bg.setFill(); panel.fill()

        var y = CGFloat(H) - 6 - 56    // top-down layout

        // Header content drawn the same way MenuHeaderView lays it out (the real
        // view is transparent, so the menu material shows behind it).
        let hx: CGFloat = 16
        if let cg = ChainRenderer.icon(for: ChainStyle.standard, size: CGSize(width: 26, height: 34)) {
            NSImage(cgImage: cg, size: NSSize(width: 26, height: 34))
                .draw(in: NSRect(x: hx, y: y + (56 - 34) / 2, width: 26, height: 34))
        }
        let htx = hx + 26 + 12
        drawLabel("NotchLock", x: htx, y: y + 28, size: 15, weight: .bold, color: dark ? .white : .black)
        drawLabel("Pull the cord to lock your screen", x: htx, y: y + 9, size: 11.5, weight: .regular,
                  color: dark ? NSColor(white: 1, alpha: 0.55) : NSColor(white: 0, alpha: 0.55))
        y -= 12
        drawSeparator(y: y + 6, W: W, dark: dark); y -= 10

        // Section header.
        drawLabel("CORD STYLE", x: 20, y: y, size: 11, weight: .semibold,
                  color: dark ? NSColor(white: 1, alpha: 0.5) : NSColor(white: 0, alpha: 0.5))
        y -= 24

        for s in styles {
            let rowRect = NSRect(x: 8, y: y - CGFloat(rowH) + 8, width: CGFloat(W - 16), height: CGFloat(rowH) - 6)
            if s == .rope {   // show one highlighted (selected) row
                (dark ? NSColor(calibratedRed: 0.30, green: 0.45, blue: 0.95, alpha: 0.9)
                      : NSColor(calibratedRed: 0.20, green: 0.42, blue: 0.95, alpha: 0.95)).setFill()
                NSBezierPath(roundedRect: rowRect, xRadius: 7, yRadius: 7).fill()
            }
            if let cg = ChainRenderer.icon(for: s.style, size: CGSize(width: 26, height: 34)) {
                NSImage(cgImage: cg, size: NSSize(width: 26, height: 34))
                    .draw(in: NSRect(x: 18, y: y - 30, width: 26, height: 34))
            }
            let hi = (s == .rope)
            drawLabel(s.displayName, x: 52, y: y - 16, size: 13, weight: .semibold,
                      color: hi ? .white : (dark ? .white : .black))
            drawLabel(s.tagline, x: 52, y: y - 32, size: 10.5, weight: .regular,
                      color: hi ? NSColor(white: 1, alpha: 0.85) : (dark ? NSColor(white: 1, alpha: 0.5) : NSColor(white: 0, alpha: 0.5)))
            if s == .rope {
                drawLabel("✓", x: CGFloat(W) - 30, y: y - 24, size: 14, weight: .bold, color: .white)
            }
            y -= CGFloat(rowH)
        }

        y -= 4; drawSeparator(y: y + 8, W: W, dark: dark); y -= 8
        for e in extras {
            drawLabel(e, x: 20, y: y - 22, size: 13, weight: .regular, color: dark ? .white : .black)
            y -= 34
        }

        NSGraphicsContext.restoreGraphicsState()
        guard let image = ctx.makeImage() else { return false }
        let url = URL(fileURLWithPath: path)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        let ok = CGImageDestinationFinalize(dest)
        if ok { FileHandle.standardOutput.write("rendered \(url.path)\n".data(using: .utf8)!) }
        return ok
    }

    private static func drawSeparator(y: CGFloat, W: Int, dark: Bool) {
        (dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.12)).setFill()
        NSRect(x: 14, y: y, width: CGFloat(W - 28), height: 1).fill()
    }

    private static func drawLabel(_ s: String, x: CGFloat, y: CGFloat, size: CGFloat,
                                  weight: NSFont.Weight, color: NSColor) {
        NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
        ]).draw(at: NSPoint(x: x, y: y))
    }


    private static func renderPose(_ engine: ChainEngine, name: String, to dir: String) {
        guard let ctx = makeContext(size: cell) else { return }
        drawScene(ctx, engine: engine)
        save(ctx, to: dir, name: name)
    }

    private static func drawScene(_ ctx: CGContext, engine: ChainEngine, label: String? = nil) {
        ctx.saveGState()
        ctx.clip(to: CGRect(origin: .zero, size: cell))   // emulate the top-edge clip
        // Soft gradient backdrop.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        if let g = CGGradient(colorsSpace: space,
                              colors: [CGColor(srgbRed: 0.14, green: 0.15, blue: 0.20, alpha: 1),
                                       CGColor(srgbRed: 0.09, green: 0.09, blue: 0.12, alpha: 1)] as CFArray,
                              locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: cell.height), end: CGPoint(x: 0, y: 0), options: [])
        }
        ChainRenderer.draw(in: ctx, state: engine.state, style: engine.style)
        // Notch nub at the top centre (the cord passes behind it).
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        let notch = CGPath(roundedRect: CGRect(x: cell.width / 2 - 70, y: cell.height - 20, width: 140, height: 28),
                           cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.addPath(notch); ctx.fillPath()
        if let label {
            let a = NSAttributedString(string: label, attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: NSColor(white: 0.96, alpha: 0.95),
            ])
            let w = a.size().width
            let g = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = g
            a.draw(at: CGPoint(x: cell.width / 2 - w / 2, y: 24))
            NSGraphicsContext.restoreGraphicsState()
        }
        ctx.restoreGState()
    }

    private static func ensureDir(_ dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    private static func makeContext(size: CGSize) -> CGContext? {
        CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func save(_ ctx: CGContext, to dir: String, name: String) {
        guard let image = ctx.makeImage() else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        FileHandle.standardOutput.write("rendered \(url.path)\n".data(using: .utf8)!)
    }
}
