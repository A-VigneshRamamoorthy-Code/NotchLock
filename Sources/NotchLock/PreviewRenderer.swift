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

    // MARK: - Helpers

    private static func renderPose(_ engine: ChainEngine, name: String, to dir: String) {
        guard let ctx = makeContext(size: cell) else { return }
        drawScene(ctx, engine: engine)
        save(ctx, to: dir, name: name)
    }

    private static func drawScene(_ ctx: CGContext, engine: ChainEngine) {
        ctx.saveGState()
        ctx.clip(to: CGRect(origin: .zero, size: cell))   // emulate the top-edge clip
        ctx.setFillColor(CGColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: cell))
        ChainRenderer.draw(in: ctx, state: engine.state, style: engine.style)
        // Notch nub at the top centre (the cord passes behind it).
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        let notch = CGPath(roundedRect: CGRect(x: cell.width / 2 - 70, y: cell.height - 20, width: 140, height: 28),
                           cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.addPath(notch); ctx.fillPath()
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
