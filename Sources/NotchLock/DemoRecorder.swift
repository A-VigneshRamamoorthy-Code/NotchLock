import AppKit
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import NotchLockCore
import UniformTypeIdentifiers

/// Records a polished product demo of NotchLock into an .mp4 (and PNG frames)
/// using the *real* `ChainEngine` + `ChainRenderer`, composited into a simulated
/// macOS desktop with a notch, a moving cursor, and a screen-lock finale.
///
/// This needs no Screen-Recording permission: every pixel is drawn from the same
/// core the live app uses, so it faithfully shows the actual behaviour.
enum DemoRecorder {
    static let W = 1280
    static let H = 800
    static let fps: Int32 = 30

    // Scene anchors (bottom-left origin, +y up).
    static var cx: CGFloat { CGFloat(W) / 2 }
    static let menuBarH: CGFloat = 34

    static func record(to dir: String) {
        let framesDir = URL(fileURLWithPath: dir).appendingPathComponent("frames")
        try? FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)
        let mp4URL = URL(fileURLWithPath: dir).appendingPathComponent("notchlock-demo.mp4")
        try? FileManager.default.removeItem(at: mp4URL)

        guard let writer = try? AVAssetWriter(outputURL: mp4URL, fileType: .mp4) else {
            FileHandle.standardError.write("failed to create writer\n".data(using: .utf8)!); return
        }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: W, AVVideoHeightKey: H,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 7_000_000,
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: W,
            kCVPixelBufferHeightKey as String: H,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // --- Engine set up like the live app (shoulder above the top edge). ---
        let shoulder = CGPoint(x: cx, y: CGFloat(H) + 16)
        var engine = ChainEngine(shoulder: shoulder, style: .standard)
        let style = ChainStyle.standard

        let totalFrames = Int(Double(fps) * 11.0)
        var grabbed = false
        var released = false

        for f in 0..<totalFrames {
            let t = Double(f) / Double(fps)
            let script = interaction(t: t, engine: engine, style: style)

            // Drive the real engine exactly like the app's handlers.
            if script.grab && !grabbed {
                _ = engine.grab(at: engine.beadPosition)
                grabbed = true
            }
            if grabbed && !released, let target = script.dragTo {
                engine.drag(to: target)
            }
            if script.release && grabbed && !released {
                _ = engine.release()
                released = true
            }
            // Step physics twice at 1/60 for smoothness/stability.
            engine.update(dt: 1.0 / 60.0, engaged: script.engaged)
            engine.update(dt: 1.0 / 60.0, engaged: script.engaged)

            let img = renderFrame(t: t, engine: engine, style: style, script: script)
            savePNG(img, to: framesDir.appendingPathComponent(String(format: "f%04d.png", f)))
            appendFrame(img, adaptor: adaptor, input: input, frame: f)
        }

        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        sem.wait()
        FileHandle.standardOutput.write("wrote \(mp4URL.path) (\(totalFrames) frames)\n".data(using: .utf8)!)
    }

    // MARK: - Interaction script

    struct Script {
        var cursor: CGPoint
        var engaged: Bool
        var grab: Bool
        var dragTo: CGPoint?
        var release: Bool
        var closedHand: Bool
        var caption: String?
        var phase: Phase
    }
    enum Phase { case intro, approach, grab, pull, release, locking, locked }

    static func interaction(t: Double, engine: ChainEngine, style: ChainStyle) -> Script {
        let beadRestY = CGFloat(H) + 16 - CGFloat(style.restLength)   // ≈ 694
        let idle = CGPoint(x: cx + 150, y: 430)
        let atBead = CGPoint(x: cx + 14, y: beadRestY)
        let pullBottom = CGPoint(x: cx + 10, y: beadRestY - 196)

        func ease(_ a: CGFloat, _ b: CGFloat, _ u: Double) -> CGFloat {
            let e = u < 0 ? 0 : (u > 1 ? 1 : u)
            let s = e * e * (3 - 2 * e)                 // smoothstep
            return a + (b - a) * CGFloat(s)
        }
        func lerpP(_ a: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
            CGPoint(x: ease(a.x, b.x, u), y: ease(a.y, b.y, u))
        }

        switch t {
        case ..<1.5:
            return Script(cursor: idle, engaged: false, grab: false, dragTo: nil, release: false,
                          closedHand: false, caption: nil, phase: .intro)
        case ..<2.7:
            let u = (t - 1.5) / 1.2
            let c = lerpP(idle, atBead, u)
            return Script(cursor: c, engaged: true, grab: false, dragTo: nil, release: false,
                          closedHand: false, caption: "Bring your cursor to the notch", phase: .approach)
        case ..<3.3:
            return Script(cursor: atBead, engaged: true, grab: false, dragTo: nil, release: false,
                          closedHand: false, caption: "Grab the pull-cord", phase: .approach)
        case ..<3.6:
            return Script(cursor: engine.beadPosition, engaged: true, grab: true, dragTo: engine.beadPosition,
                          release: false, closedHand: true, caption: "Grab the pull-cord", phase: .grab)
        case ..<5.3:
            let u = (t - 3.6) / 1.7
            let c = lerpP(atBead, pullBottom, u)
            return Script(cursor: c, engaged: true, grab: false, dragTo: c, release: false,
                          closedHand: true, caption: "Pull it down…", phase: .pull)
        case ..<5.6:
            return Script(cursor: pullBottom, engaged: true, grab: false, dragTo: pullBottom, release: false,
                          closedHand: true, caption: "Pull it down…", phase: .pull)
        case ..<5.75:
            return Script(cursor: pullBottom, engaged: true, grab: false, dragTo: nil, release: true,
                          closedHand: false, caption: "…and let go!", phase: .release)
        case ..<7.3:
            let u = (t - 5.75) / 1.2
            let c = lerpP(pullBottom, CGPoint(x: cx + 190, y: beadRestY - 30), u)
            return Script(cursor: c, engaged: true, grab: false, dragTo: nil, release: false,
                          closedHand: false, caption: "…and let go!", phase: .release)
        case ..<7.7:
            return Script(cursor: CGPoint(x: cx + 190, y: beadRestY - 30), engaged: false, grab: false,
                          dragTo: nil, release: false, closedHand: false,
                          caption: "Locking your Mac…", phase: .locking)
        default:
            return Script(cursor: CGPoint(x: cx + 190, y: beadRestY - 30), engaged: false, grab: false,
                          dragTo: nil, release: false, closedHand: false,
                          caption: nil, phase: .locked)
        }
    }

    // MARK: - Frame rendering

    static func renderFrame(t: Double, engine: ChainEngine, style: ChainStyle, script: Script) -> CGImage {
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns

        drawWallpaper(ctx)
        drawDock(ctx)

        // Cord (real renderer), then the menu bar/notch on top so the cord's top
        // is hidden behind the notch, exactly like the live app.
        ChainRenderer.draw(in: ctx, state: engine.state, style: style)
        drawMenuBar(ctx, t: t)

        drawCursor(ctx, at: script.cursor, closedHand: script.closedHand, phase: script.phase)
        drawCaption(ctx, script.caption)

        if script.phase == .intro { drawIntro(ctx, t: t) }

        // Lock finale: a quick flash then the lock screen.
        switch script.phase {
        case .locking:
            drawLockGlow(ctx, t: t)
        case .locked:
            drawLockScreen(ctx, t: t)
        default:
            break
        }

        drawVignette(ctx)

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    private static func drawWallpaper(_ ctx: CGContext) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let cols = [CGColor(srgbRed: 0.10, green: 0.13, blue: 0.26, alpha: 1),
                    CGColor(srgbRed: 0.16, green: 0.10, blue: 0.24, alpha: 1),
                    CGColor(srgbRed: 0.06, green: 0.07, blue: 0.12, alpha: 1)]
        if let g = CGGradient(colorsSpace: space, colors: cols as CFArray, locations: [0, 0.5, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: H), end: CGPoint(x: CGFloat(W), y: 0), options: [])
        }
        // Soft aurora blobs.
        for (bx, by, br, c) in [(0.24, 0.30, 0.5, CGColor(srgbRed: 0.30, green: 0.44, blue: 0.95, alpha: 0.18)),
                                (0.80, 0.72, 0.6, CGColor(srgbRed: 0.70, green: 0.36, blue: 0.85, alpha: 0.16))] {
            ctx.saveGState()
            ctx.setFillColor(c)
            let r = CGFloat(br) * CGFloat(W)
            ctx.fillEllipse(in: CGRect(x: CGFloat(bx) * CGFloat(W) - r, y: CGFloat(by) * CGFloat(H) - r,
                                       width: r * 2, height: r * 2))
            ctx.restoreGState()
        }
    }

    private static func drawDock(_ ctx: CGContext) {
        let dockW: CGFloat = 520, dockH: CGFloat = 60
        let rect = CGRect(x: cx - dockW / 2, y: 18, width: dockW, height: dockH)
        ctx.saveGState()
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil))
        ctx.fillPath()
        let tiles = 7
        let gap: CGFloat = 12
        let tile = (dockW - gap * CGFloat(tiles + 1)) / CGFloat(tiles)
        let colors: [CGColor] = [
            CGColor(srgbRed: 0.36, green: 0.55, blue: 0.98, alpha: 0.9),
            CGColor(srgbRed: 0.42, green: 0.80, blue: 0.55, alpha: 0.9),
            CGColor(srgbRed: 0.98, green: 0.62, blue: 0.32, alpha: 0.9),
            CGColor(srgbRed: 0.86, green: 0.42, blue: 0.72, alpha: 0.9),
            CGColor(srgbRed: 0.55, green: 0.52, blue: 0.95, alpha: 0.9),
            CGColor(srgbRed: 0.40, green: 0.78, blue: 0.86, alpha: 0.9),
            CGColor(srgbRed: 0.92, green: 0.78, blue: 0.36, alpha: 0.9),
        ]
        for i in 0..<tiles {
            let x = rect.minX + gap + CGFloat(i) * (tile + gap)
            ctx.setFillColor(colors[i % colors.count])
            ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: rect.minY + (dockH - tile) / 2, width: tile, height: tile),
                               cornerWidth: tile * 0.24, cornerHeight: tile * 0.24, transform: nil))
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    private static func drawMenuBar(_ ctx: CGContext, t: Double) {
        let barRect = CGRect(x: 0, y: CGFloat(H) - menuBarH, width: CGFloat(W), height: menuBarH)
        ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.05, blue: 0.07, alpha: 0.86))
        ctx.fill(barRect)

        // The notch cutout (pure black, rounded lower corners) at top-centre.
        let nW: CGFloat = 200, nH: CGFloat = menuBarH + 8
        let notch = CGRect(x: cx - nW / 2, y: CGFloat(H) - nH, width: nW, height: nH)
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.addPath(bottomRoundedPath(notch, radius: 14))
        ctx.fillPath()

        // Left menu-bar text.
        drawText("NotchLock", at: CGPoint(x: 58, y: CGFloat(H) - 23), size: 13, weight: .semibold, color: NSColor(white: 1, alpha: 0.92))
        drawText("File   Edit   View", at: CGPoint(x: 150, y: CGFloat(H) - 23), size: 12.5, color: NSColor(white: 1, alpha: 0.6))
        drawAppleLogo(ctx, at: CGPoint(x: 26, y: CGFloat(H) - menuBarH / 2))
        // Right side status + clock (laid out right-to-left, no overlaps).
        drawText("9:41 AM", at: CGPoint(x: CGFloat(W) - 84, y: CGFloat(H) - 23), size: 12.5, weight: .medium, color: NSColor(white: 1, alpha: 0.9))
        drawText("Wed 3 Jul", at: CGPoint(x: CGFloat(W) - 250, y: CGFloat(H) - 23), size: 12.5, color: NSColor(white: 1, alpha: 0.72))
        drawStatusGlyphs(ctx)
    }

    private static func drawStatusGlyphs(_ ctx: CGContext) {
        ctx.saveGState()
        // wifi arcs
        let wx = CGFloat(W) - 146, wy = CGFloat(H) - 20
        for (i, r) in [10.0, 7.0, 4.0].enumerated() {
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.72 - Double(i) * 0.12))
            ctx.setLineWidth(2)
            ctx.addArc(center: CGPoint(x: wx, y: wy - 4), radius: CGFloat(r), startAngle: .pi * 0.75, endAngle: .pi * 0.25, clockwise: true)
            ctx.strokePath()
        }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.72))
        ctx.fillEllipse(in: CGRect(x: wx - 1.5, y: wy - 6.5, width: 3, height: 3))
        // battery
        let bat = CGRect(x: CGFloat(W) - 124, y: CGFloat(H) - 24, width: 22, height: 11)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.6)); ctx.setLineWidth(1.2)
        ctx.stroke(bat)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85))
        ctx.fill(bat.insetBy(dx: 2, dy: 2))
        ctx.fill(CGRect(x: bat.maxX, y: bat.midY - 2.5, width: 2, height: 5))
        ctx.restoreGState()
    }

    private static func drawAppleLogo(_ ctx: CGContext, at c: CGPoint) {
        // A simple rounded apple silhouette.
        ctx.saveGState()
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9))
        let r: CGFloat = 7
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r - 1, width: r * 2, height: r * 2))
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r + 3, width: r * 2, height: r * 2 - 3))
        // leaf
        ctx.fillEllipse(in: CGRect(x: c.x + 1, y: c.y + r - 2, width: 5, height: 6))
        // bite
        ctx.setBlendMode(.clear)
        ctx.fillEllipse(in: CGRect(x: c.x + r - 3, y: c.y - 3, width: 7, height: 7))
        ctx.restoreGState()
    }

    // MARK: - Cursor

    private static func drawCursor(_ ctx: CGContext, at p: CGPoint, closedHand: Bool, phase: Phase) {
        if phase == .locked { return }
        let cursor: NSCursor = closedHand ? .closedHand : (phase == .approach || phase == .grab ? .openHand : .arrow)
        let img = cursor.image
        let scale: CGFloat = 1.7
        let sz = NSSize(width: img.size.width * scale, height: img.size.height * scale)
        // Hotspot: arrow = top-left; hands ≈ centre.
        let origin: CGPoint
        if closedHand || cursor == NSCursor.openHand {
            origin = CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2)
        } else {
            origin = CGPoint(x: p.x, y: p.y - sz.height)
        }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 5,
                      color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5))
        img.draw(in: NSRect(origin: origin, size: sz), from: .zero, operation: .sourceOver, fraction: 1)
        ctx.restoreGState()
    }

    // MARK: - Captions / intro / lock

    private static func drawCaption(_ ctx: CGContext, _ text: String?) {
        guard let text, !text.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: 26, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let s = NSAttributedString(string: text, attributes: attrs)
        let tw = s.size().width
        let padX: CGFloat = 26, padY: CGFloat = 13
        let pillW = tw + padX * 2, pillH: CGFloat = 52
        let rect = CGRect(x: cx - pillW / 2, y: 108, width: pillW, height: pillH)
        ctx.saveGState()
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: pillH / 2, cornerHeight: pillH / 2, transform: nil))
        ctx.fillPath()
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12)); ctx.setLineWidth(1)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: pillH / 2, cornerHeight: pillH / 2, transform: nil))
        ctx.strokePath()
        s.draw(at: CGPoint(x: cx - tw / 2, y: rect.minY + padY))
        ctx.restoreGState()
    }

    private static func drawIntro(_ ctx: CGContext, t: Double) {
        let a = CGFloat(t < 1.0 ? 1.0 : max(0, 1 - (t - 1.0) / 0.5))
        drawCenteredTitle(ctx, "NotchLock", sub: "pull the cord to lock your Mac", alpha: a, y: 430)
    }

    private static func drawCenteredTitle(_ ctx: CGContext, _ title: String, sub: String, alpha: CGFloat, y: CGFloat) {
        let tf = NSFont.systemFont(ofSize: 66, weight: .heavy)
        let ts = NSAttributedString(string: title, attributes: [.font: tf, .foregroundColor: NSColor(white: 1, alpha: alpha)])
        let tw = ts.size().width
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 18,
                      color: CGColor(srgbRed: 0.4, green: 0.3, blue: 0.9, alpha: Double(alpha) * 0.8))
        ts.draw(at: CGPoint(x: cx - tw / 2, y: y))
        ctx.restoreGState()
        let sf = NSFont.systemFont(ofSize: 22, weight: .medium)
        let ss = NSAttributedString(string: sub, attributes: [.font: sf, .foregroundColor: NSColor(white: 0.85, alpha: alpha)])
        let sw = ss.size().width
        ss.draw(at: CGPoint(x: cx - sw / 2, y: y - 40))
    }

    private static func drawLockGlow(_ ctx: CGContext, t: Double) {
        // Amber → red pulse building up as the lock arms.
        let u = (t - 7.3) / 0.4
        let a = CGFloat(min(0.5, u * 0.5))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.4, blue: 0.35, alpha: Double(a)))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    }

    private static func drawLockScreen(_ ctx: CGContext, t: Double) {
        let fadeIn = CGFloat(min(1, (t - 7.7) / 0.35))
        // White flash decaying into the lock screen.
        if t < 7.9 {
            let flash = CGFloat(max(0, 1 - (t - 7.7) / 0.2))
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: Double(flash) * 0.9))
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        }
        // Darkened, blurred-feeling wallpaper.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        ctx.saveGState()
        ctx.setAlpha(fadeIn)
        let cols = [CGColor(srgbRed: 0.05, green: 0.06, blue: 0.13, alpha: 1),
                    CGColor(srgbRed: 0.02, green: 0.02, blue: 0.05, alpha: 1)]
        if let g = CGGradient(colorsSpace: space, colors: cols as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
        }

        // Big clock + date.
        let clockF = NSFont.systemFont(ofSize: 96, weight: .bold)
        let clock = NSAttributedString(string: "9:41", attributes: [.font: clockF, .foregroundColor: NSColor(white: 1, alpha: fadeIn)])
        let cw = clock.size().width
        clock.draw(at: CGPoint(x: cx - cw / 2, y: 470))
        let dateF = NSFont.systemFont(ofSize: 24, weight: .medium)
        let date = NSAttributedString(string: "Wednesday, 3 July", attributes: [.font: dateF, .foregroundColor: NSColor(white: 0.85, alpha: fadeIn)])
        let dw = date.size().width
        date.draw(at: CGPoint(x: cx - dw / 2, y: 440))

        // Padlock badge.
        drawPadlock(ctx, center: CGPoint(x: cx, y: 300), scale: 1.0, alpha: fadeIn)

        // "Locked by NotchLock"
        let lf = NSFont.systemFont(ofSize: 22, weight: .semibold)
        let locked = NSAttributedString(string: "Locked by NotchLock", attributes: [.font: lf, .foregroundColor: NSColor(white: 0.92, alpha: fadeIn)])
        let lw = locked.size().width
        locked.draw(at: CGPoint(x: cx - lw / 2, y: 232))

        // Password field hint.
        let pill = CGRect(x: cx - 150, y: 180, width: 300, height: 40)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: Double(fadeIn) * 0.12))
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 20, cornerHeight: 20, transform: nil))
        ctx.fillPath()
        let hf = NSFont.systemFont(ofSize: 15, weight: .regular)
        let hint = NSAttributedString(string: "Enter Password", attributes: [.font: hf, .foregroundColor: NSColor(white: 0.7, alpha: fadeIn)])
        let hw = hint.size().width
        hint.draw(at: CGPoint(x: cx - hw / 2, y: pill.minY + 11))
        ctx.restoreGState()
    }

    private static func drawPadlock(_ ctx: CGContext, center c: CGPoint, scale s: CGFloat, alpha: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.scaleBy(x: s, y: s)
        // Shackle.
        ctx.setStrokeColor(CGColor(srgbRed: 0.9, green: 0.92, blue: 1, alpha: Double(alpha)))
        ctx.setLineWidth(10)
        ctx.addArc(center: CGPoint(x: 0, y: 18), radius: 22, startAngle: 0, endAngle: .pi, clockwise: false)
        ctx.move(to: CGPoint(x: -22, y: 18)); ctx.addLine(to: CGPoint(x: -22, y: 4))
        ctx.move(to: CGPoint(x: 22, y: 18)); ctx.addLine(to: CGPoint(x: 22, y: 4))
        ctx.strokePath()
        // Body.
        let body = CGRect(x: -34, y: -40, width: 68, height: 52)
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [CGColor(srgbRed: 0.95, green: 0.80, blue: 0.42, alpha: Double(alpha)),
                                       CGColor(srgbRed: 0.82, green: 0.62, blue: 0.24, alpha: Double(alpha))] as CFArray,
                              locations: [0, 1]) {
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: body, cornerWidth: 12, cornerHeight: 12, transform: nil)); ctx.clip()
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
            ctx.restoreGState()
        }
        // Keyhole.
        ctx.setFillColor(CGColor(srgbRed: 0.15, green: 0.10, blue: 0.03, alpha: Double(alpha)))
        ctx.fillEllipse(in: CGRect(x: -7, y: -18, width: 14, height: 14))
        ctx.beginPath()
        ctx.move(to: CGPoint(x: -4, y: -14)); ctx.addLine(to: CGPoint(x: 4, y: -14))
        ctx.addLine(to: CGPoint(x: 7, y: -32)); ctx.addLine(to: CGPoint(x: -7, y: -32))
        ctx.closePath(); ctx.fillPath()
        ctx.restoreGState()
    }

    private static func drawVignette(_ ctx: CGContext) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        if let g = CGGradient(colorsSpace: space,
                              colors: [CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0),
                                       CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28)] as CFArray,
                              locations: [0.6, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: CGFloat(H) / 2), startRadius: 0,
                                   endCenter: CGPoint(x: cx, y: CGFloat(H) / 2), endRadius: CGFloat(W) * 0.62, options: [])
        }
    }

    // MARK: - Helpers

    private static func drawText(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) {
        guard !s.isEmpty, size > 0 else { return }
        let a = NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
        ])
        a.draw(at: p)
    }

    private static func bottomRoundedPath(_ r: CGRect, radius: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + radius), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }

    private static func appendFrame(_ img: CGImage, adaptor: AVAssetWriterInputPixelBufferAdaptor,
                                    input: AVAssetWriterInput, frame: Int) {
        guard let pool = adaptor.pixelBufferPool else { return }
        var pbOut: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pbOut)
        guard let pb = pbOut else { return }
        CVPixelBufferLockBaseAddress(pb, [])
        if let base = CVPixelBufferGetBaseAddress(pb) {
            let ctx = CGContext(data: base, width: W, height: H, bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            ctx?.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        while !input.isReadyForMoreMediaData { usleep(2000) }
        adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
    }

    private static func savePNG(_ img: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }
}
