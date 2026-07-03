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
/// macOS desktop. Shows: proximity reveal + playful sway → the right-click style
/// menu (pick **Thick Rope**) → grab, pull, swing → the Mac locks.
enum DemoRecorder {
    static let W = 1280
    static let H = 800
    static let fps: Int32 = 30
    static var cx: CGFloat { CGFloat(W) / 2 }
    static let menuBarH: CGFloat = 34

    enum Phase { case intro, approach, menu, settle, grab, pull, release, locking, locked }

    struct Frame {
        var cursor: CGPoint
        var caption: String?
        var phase: Phase
        var closedHand: Bool = false
        var showMenu: Bool = false
        var menuHighlight: Int = -1
        var selectedStyle: Int = 1        // which row shows a checkmark (1 = Thick Rope)
        var introT: Double = 0
        var lockT: Double = 0
    }

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
            kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Start on the brass cord; switch to Thick Rope when the menu selects it.
        let shoulder = CGPoint(x: cx, y: CGFloat(H) + 16)
        var engine = ChainEngine(shoulder: shoulder, style: CordStyle.brass.style)
        var styleNow = CordStyle.brass

        // Frame timeline (30fps).
        let F_INTRO = 45,   F_APPROACH = 82,  F_MENU = 172, F_SETTLE = 202
        let F_GRAB = 212,   F_PULL = 250,     F_RELEASE = 258, F_SWING = 268
        let F_LOCKING = 270, F_LOCKED = 272,  F_END = 372
        let switchFrame = 152            // menu selection commits → cord becomes rope
        let ropeStyle = CordStyle.rope
        // Notch span the cord can drop from (matches the drawn notch, inset a bit).
        let notchMin = cx - 88, notchMax = cx + 88
        let shoulderY = CGFloat(H) + 16

        var grabbed = false, released = false
        var grabBead = CGPoint.zero

        for f in 0..<F_END {
            // --- Build this frame's script ---
            var fr = Frame(cursor: CGPoint(x: cx - 150, y: 430), caption: nil, phase: .intro)

            if f < F_INTRO {
                fr.phase = .intro; fr.introT = Double(f) / Double(fps)
                fr.cursor = CGPoint(x: cx - 150, y: 430)
            } else if f < F_APPROACH {
                fr.phase = .approach; fr.caption = "The cord drops in line with your cursor"
                let u = smooth(Double(f - F_INTRO) / Double(F_APPROACH - F_INTRO))
                // Approach from the LEFT so the cord drops off-centre under the pointer.
                fr.cursor = lerp(CGPoint(x: cx - 150, y: 430), CGPoint(x: cx - 96, y: 700), u)
            } else if f < F_MENU {
                fr.phase = .menu; fr.caption = "Right‑click the notch to pick a style"
                fr.showMenu = true
                let mu = Double(f - F_APPROACH) / Double(F_MENU - F_APPROACH)
                let rows = 4
                let hi = min(rows - 1, Int(mu * 5.2))
                fr.menuHighlight = hi <= 1 ? hi : (mu > 0.72 ? 1 : hi)   // linger on Thick Rope
                fr.cursor = menuCursor(forRow: fr.menuHighlight)
                if f >= switchFrame { fr.menuHighlight = 1 }
            } else if f < F_SETTLE {
                fr.phase = .settle; fr.caption = "Thick Rope selected"
                fr.cursor = CGPoint(x: cx - 92, y: 560)
            } else if f < F_GRAB {
                fr.phase = .grab; fr.caption = "Grab the pull‑cord"
                fr.closedHand = true
                fr.cursor = engineBeadGlobal(engine)
            } else if f < F_PULL {
                fr.phase = .pull; fr.caption = "Pull it down…"; fr.closedHand = true
                let u = smooth(Double(f - F_GRAB) / Double(F_PULL - F_GRAB))
                fr.cursor = CGPoint(x: grabBead.x + 8, y: grabBead.y - 210 * u)
            } else if f < F_RELEASE {
                fr.phase = .pull; fr.caption = "Pull it down…"; fr.closedHand = true
                fr.cursor = CGPoint(x: grabBead.x + 8, y: grabBead.y - 210)
            } else if f < F_SWING {
                fr.phase = .release; fr.caption = "…let go — locks instantly!"
                let u = smooth(Double(f - F_RELEASE) / Double(F_SWING - F_RELEASE))
                fr.cursor = lerp(CGPoint(x: grabBead.x + 8, y: grabBead.y - 210),
                                 CGPoint(x: grabBead.x + 70, y: grabBead.y - 120), u)
            } else if f < F_LOCKING {
                fr.phase = .locking; fr.caption = nil
                fr.cursor = CGPoint(x: grabBead.x + 70, y: grabBead.y - 120); fr.lockT = Double(f - F_SWING) / Double(fps)
            } else {
                fr.phase = .locked; fr.lockT = Double(f - F_LOCKED) / Double(fps)
            }

            // --- Style switch when the menu commits the choice ---
            if f == switchFrame, styleNow != ropeStyle {
                engine.style = ropeStyle.style   // rebuilds → thick rope drops back in
                styleNow = ropeStyle
                grabbed = false
            }

            // --- Drive the real engine like the app's handlers ---
            let engaged = fr.phase != .intro && fr.phase != .locking && fr.phase != .locked
            // Issue #1: the cord drops from the notch point nearest the cursor's x.
            if !grabbed {
                let sx = min(max(fr.cursor.x, notchMin), notchMax)
                engine.shoulder = CGPoint(x: sx, y: shoulderY)
            }
            if fr.phase == .grab && !grabbed {
                _ = engine.grab(at: engine.beadPosition)
                grabbed = true
                grabBead = engineBeadGlobal(engine)
            }
            if grabbed && !released && (fr.phase == .grab || fr.phase == .pull) {
                engine.drag(to: CGPoint(x: fr.cursor.x, y: fr.cursor.y))
            }
            if fr.phase == .release && grabbed && !released {
                _ = engine.release(); released = true
            }
            engine.update(dt: 1.0 / 60.0, engaged: engaged)
            engine.update(dt: 1.0 / 60.0, engaged: engaged)

            let img = renderFrame(engine: engine, fr: fr)
            savePNG(img, to: framesDir.appendingPathComponent(String(format: "f%04d.png", f)))
            appendFrame(img, adaptor: adaptor, input: input, frame: f)
        }

        input.markAsFinished()
        let sem = DispatchSemaphore(value: 0)
        writer.finishWriting { sem.signal() }
        sem.wait()
        FileHandle.standardOutput.write("wrote \(mp4URL.path) (\(F_END) frames)\n".data(using: .utf8)!)
    }

    private static func engineBeadGlobal(_ engine: ChainEngine) -> CGPoint { engine.beadPosition }

    // MARK: - Menu geometry

    static let menuRect = CGRect(x: cx - 172, y: CGFloat(H) - 40 - 232, width: 300, height: 232)
    static func menuCursor(forRow row: Int) -> CGPoint {
        let r = max(0, row)
        let y = menuRect.maxY - 44 - CGFloat(r) * 46 - 20
        return CGPoint(x: menuRect.minX + 40, y: y)
    }

    // MARK: - Frame rendering

    static func renderFrame(engine: ChainEngine, fr: Frame) -> CGImage {
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns

        drawWallpaper(ctx)
        drawDock(ctx)
        ChainRenderer.draw(in: ctx, state: engine.state, style: engine.style)
        drawMenuBar(ctx)

        if fr.showMenu { drawStyleMenu(ctx, highlight: fr.menuHighlight, selected: fr.selectedStyle) }

        drawCursor(ctx, at: fr.cursor, closedHand: fr.closedHand, phase: fr.phase, menu: fr.showMenu)
        drawCaption(ctx, fr.caption)
        if fr.phase == .intro { drawIntro(ctx, t: fr.introT) }
        if fr.phase == .locking { drawLockGlow(ctx, t: fr.lockT) }
        if fr.phase == .locked { drawLockScreen(ctx, t: fr.lockT) }
        drawVignette(ctx)

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()!
    }

    // MARK: - Style menu (mirrors the real right-click menu)

    private static func drawStyleMenu(_ ctx: CGContext, highlight: Int, selected: Int) {
        let r = menuRect
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 24, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5))
        ctx.setFillColor(CGColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 0.98))
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 14, cornerHeight: 14, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08)); ctx.setLineWidth(1)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 14, cornerHeight: 14, transform: nil)); ctx.strokePath()

        drawText("Cord style", at: CGPoint(x: r.minX + 18, y: r.maxY - 26), size: 12, weight: .semibold,
                 color: NSColor(white: 1, alpha: 0.55))

        let styles = CordStyle.allCases
        let rowH: CGFloat = 46
        for (i, s) in styles.enumerated() {
            let top = r.maxY - 40 - CGFloat(i) * rowH
            let row = CGRect(x: r.minX + 6, y: top - rowH + 8, width: r.width - 12, height: rowH - 6)
            if i == highlight {
                ctx.setFillColor(CGColor(srgbRed: 0.30, green: 0.45, blue: 0.95, alpha: 0.9))
                ctx.addPath(CGPath(roundedRect: row, cornerWidth: 8, cornerHeight: 8, transform: nil)); ctx.fillPath()
            }
            // Thumbnail.
            if let cg = ChainRenderer.icon(for: s.style, size: CGSize(width: 26, height: 34)) {
                let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
                NSImage(cgImage: cg, size: NSSize(width: 26, height: 34))
                    .draw(in: NSRect(x: row.minX + 8, y: row.midY - 17, width: 26, height: 34))
                NSGraphicsContext.restoreGraphicsState()
            }
            let nameColor = i == highlight ? NSColor.white : NSColor(white: 0.96, alpha: 1)
            let subColor = i == highlight ? NSColor(white: 1, alpha: 0.85) : NSColor(white: 1, alpha: 0.5)
            drawText(s.displayName, at: CGPoint(x: row.minX + 44, y: row.midY + 2), size: 13.5, weight: .semibold, color: nameColor)
            drawText(s.tagline, at: CGPoint(x: row.minX + 44, y: row.midY - 15), size: 10.5, color: subColor)
            if i == selected {
                drawText("✓", at: CGPoint(x: row.maxX - 24, y: row.midY - 7), size: 15, weight: .bold,
                         color: i == highlight ? .white : NSColor(srgbRed: 0.45, green: 0.7, blue: 1, alpha: 1))
            }
        }
    }

    // MARK: - Scene chrome

    private static func drawWallpaper(_ ctx: CGContext) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let cols = [CGColor(srgbRed: 0.10, green: 0.13, blue: 0.26, alpha: 1),
                    CGColor(srgbRed: 0.16, green: 0.10, blue: 0.24, alpha: 1),
                    CGColor(srgbRed: 0.06, green: 0.07, blue: 0.12, alpha: 1)]
        if let g = CGGradient(colorsSpace: space, colors: cols as CFArray, locations: [0, 0.5, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: H), end: CGPoint(x: CGFloat(W), y: 0), options: [])
        }
        for (bx, by, br, c) in [(0.24, 0.30, 0.5, CGColor(srgbRed: 0.30, green: 0.44, blue: 0.95, alpha: 0.18)),
                                (0.80, 0.72, 0.6, CGColor(srgbRed: 0.70, green: 0.36, blue: 0.85, alpha: 0.16))] {
            ctx.saveGState(); ctx.setFillColor(c)
            let rr = CGFloat(br) * CGFloat(W)
            ctx.fillEllipse(in: CGRect(x: CGFloat(bx) * CGFloat(W) - rr, y: CGFloat(by) * CGFloat(H) - rr, width: rr * 2, height: rr * 2))
            ctx.restoreGState()
        }
    }

    private static func drawDock(_ ctx: CGContext) {
        let dockW: CGFloat = 520, dockH: CGFloat = 60
        let rect = CGRect(x: cx - dockW / 2, y: 18, width: dockW, height: dockH)
        ctx.saveGState()
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil)); ctx.fillPath()
        let tiles = 7, gap: CGFloat = 12
        let tile = (dockW - gap * CGFloat(tiles + 1)) / CGFloat(tiles)
        let colors: [CGColor] = [CGColor(srgbRed: 0.36, green: 0.55, blue: 0.98, alpha: 0.9),
                                 CGColor(srgbRed: 0.42, green: 0.80, blue: 0.55, alpha: 0.9),
                                 CGColor(srgbRed: 0.98, green: 0.62, blue: 0.32, alpha: 0.9),
                                 CGColor(srgbRed: 0.86, green: 0.42, blue: 0.72, alpha: 0.9),
                                 CGColor(srgbRed: 0.55, green: 0.52, blue: 0.95, alpha: 0.9),
                                 CGColor(srgbRed: 0.40, green: 0.78, blue: 0.86, alpha: 0.9),
                                 CGColor(srgbRed: 0.92, green: 0.78, blue: 0.36, alpha: 0.9)]
        for i in 0..<tiles {
            let x = rect.minX + gap + CGFloat(i) * (tile + gap)
            ctx.setFillColor(colors[i % colors.count])
            ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: rect.minY + (dockH - tile) / 2, width: tile, height: tile),
                               cornerWidth: tile * 0.24, cornerHeight: tile * 0.24, transform: nil)); ctx.fillPath()
        }
        ctx.restoreGState()
    }

    private static func drawMenuBar(_ ctx: CGContext) {
        let barRect = CGRect(x: 0, y: CGFloat(H) - menuBarH, width: CGFloat(W), height: menuBarH)
        ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.05, blue: 0.07, alpha: 0.86)); ctx.fill(barRect)
        let nW: CGFloat = 200, nH: CGFloat = menuBarH + 8
        let notch = CGRect(x: cx - nW / 2, y: CGFloat(H) - nH, width: nW, height: nH)
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.addPath(bottomRoundedPath(notch, radius: 14)); ctx.fillPath()
        drawText("NotchLock", at: CGPoint(x: 58, y: CGFloat(H) - 23), size: 13, weight: .semibold, color: NSColor(white: 1, alpha: 0.92))
        drawText("File   Edit   View", at: CGPoint(x: 150, y: CGFloat(H) - 23), size: 12.5, color: NSColor(white: 1, alpha: 0.6))
        drawAppleLogo(ctx, at: CGPoint(x: 26, y: CGFloat(H) - menuBarH / 2))
        drawText("9:41 AM", at: CGPoint(x: CGFloat(W) - 84, y: CGFloat(H) - 23), size: 12.5, weight: .medium, color: NSColor(white: 1, alpha: 0.9))
        drawText("Wed 3 Jul", at: CGPoint(x: CGFloat(W) - 250, y: CGFloat(H) - 23), size: 12.5, color: NSColor(white: 1, alpha: 0.72))
        drawStatusGlyphs(ctx)
    }

    private static func drawStatusGlyphs(_ ctx: CGContext) {
        ctx.saveGState()
        let wx = CGFloat(W) - 146, wy = CGFloat(H) - 20
        for (i, r) in [10.0, 7.0, 4.0].enumerated() {
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.72 - Double(i) * 0.12)); ctx.setLineWidth(2)
            ctx.addArc(center: CGPoint(x: wx, y: wy - 4), radius: CGFloat(r), startAngle: .pi * 0.75, endAngle: .pi * 0.25, clockwise: true); ctx.strokePath()
        }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.72))
        ctx.fillEllipse(in: CGRect(x: wx - 1.5, y: wy - 6.5, width: 3, height: 3))
        let bat = CGRect(x: CGFloat(W) - 124, y: CGFloat(H) - 24, width: 22, height: 11)
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.6)); ctx.setLineWidth(1.2); ctx.stroke(bat)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85)); ctx.fill(bat.insetBy(dx: 2, dy: 2))
        ctx.fill(CGRect(x: bat.maxX, y: bat.midY - 2.5, width: 2, height: 5))
        ctx.restoreGState()
    }

    private static func drawAppleLogo(_ ctx: CGContext, at c: CGPoint) {
        ctx.saveGState(); ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9))
        let r: CGFloat = 7
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r - 1, width: r * 2, height: r * 2))
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r + 3, width: r * 2, height: r * 2 - 3))
        ctx.fillEllipse(in: CGRect(x: c.x + 1, y: c.y + r - 2, width: 5, height: 6))
        ctx.setBlendMode(.clear); ctx.fillEllipse(in: CGRect(x: c.x + r - 3, y: c.y - 3, width: 7, height: 7))
        ctx.restoreGState()
    }

    private static func drawCursor(_ ctx: CGContext, at p: CGPoint, closedHand: Bool, phase: Phase, menu: Bool) {
        if phase == .locked { return }
        let cursor: NSCursor
        if menu { cursor = .arrow }
        else if closedHand { cursor = .closedHand }
        else if phase == .approach || phase == .grab || phase == .settle { cursor = .openHand }
        else { cursor = .arrow }
        let img = cursor.image
        let scale: CGFloat = 1.7
        let sz = NSSize(width: img.size.width * scale, height: img.size.height * scale)
        let origin: CGPoint
        if !menu && (closedHand || cursor == NSCursor.openHand) {
            origin = CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2)
        } else {
            origin = CGPoint(x: p.x, y: p.y - sz.height)
        }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 5, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5))
        img.draw(in: NSRect(origin: origin, size: sz), from: .zero, operation: .sourceOver, fraction: 1)
        ctx.restoreGState()
    }

    private static func drawCaption(_ ctx: CGContext, _ text: String?) {
        guard let text, !text.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: 26, weight: .semibold)
        let s = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white])
        let tw = s.size().width
        let padX: CGFloat = 26, padY: CGFloat = 13
        let pillW = tw + padX * 2, pillH: CGFloat = 52
        let rect = CGRect(x: cx - pillW / 2, y: 96, width: pillW, height: pillH)
        ctx.saveGState()
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: pillH / 2, cornerHeight: pillH / 2, transform: nil)); ctx.fillPath()
        ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.12)); ctx.setLineWidth(1)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: pillH / 2, cornerHeight: pillH / 2, transform: nil)); ctx.strokePath()
        s.draw(at: CGPoint(x: cx - tw / 2, y: rect.minY + padY))
        ctx.restoreGState()
    }

    private static func drawIntro(_ ctx: CGContext, t: Double) {
        let a = CGFloat(t < 1.0 ? 1.0 : max(0, 1 - (t - 1.0) / 0.5))
        let tf = NSFont.systemFont(ofSize: 66, weight: .heavy)
        let ts = NSAttributedString(string: "NotchLock", attributes: [.font: tf, .foregroundColor: NSColor(white: 1, alpha: a)])
        let tw = ts.size().width
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 18, color: CGColor(srgbRed: 0.4, green: 0.3, blue: 0.9, alpha: Double(a) * 0.8))
        ts.draw(at: CGPoint(x: cx - tw / 2, y: 430))
        ctx.restoreGState()
        let sf = NSFont.systemFont(ofSize: 22, weight: .medium)
        let ss = NSAttributedString(string: "pull the cord to lock your Mac", attributes: [.font: sf, .foregroundColor: NSColor(white: 0.85, alpha: a)])
        ss.draw(at: CGPoint(x: cx - ss.size().width / 2, y: 390))
    }

    private static func drawLockGlow(_ ctx: CGContext, t: Double) {
        let a = CGFloat(min(0.5, (t / 0.4) * 0.5))
        ctx.setFillColor(CGColor(srgbRed: 1, green: 0.4, blue: 0.35, alpha: Double(a)))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    }

    private static func drawLockScreen(_ ctx: CGContext, t: Double) {
        let fadeIn = CGFloat(min(1, t / 0.35))
        if t < 0.2 {
            let flash = CGFloat(max(0, 1 - t / 0.2))
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: Double(flash) * 0.9)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        ctx.saveGState(); ctx.setAlpha(fadeIn)
        if let g = CGGradient(colorsSpace: space, colors: [CGColor(srgbRed: 0.05, green: 0.06, blue: 0.13, alpha: 1),
                                                           CGColor(srgbRed: 0.02, green: 0.02, blue: 0.05, alpha: 1)] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
        }
        let clockF = NSFont.systemFont(ofSize: 96, weight: .bold)
        let clock = NSAttributedString(string: "9:41", attributes: [.font: clockF, .foregroundColor: NSColor(white: 1, alpha: fadeIn)])
        clock.draw(at: CGPoint(x: cx - clock.size().width / 2, y: 470))
        let dateF = NSFont.systemFont(ofSize: 24, weight: .medium)
        let date = NSAttributedString(string: "Wednesday, 3 July", attributes: [.font: dateF, .foregroundColor: NSColor(white: 0.85, alpha: fadeIn)])
        date.draw(at: CGPoint(x: cx - date.size().width / 2, y: 440))
        drawPadlock(ctx, center: CGPoint(x: cx, y: 300), alpha: fadeIn)
        let lf = NSFont.systemFont(ofSize: 22, weight: .semibold)
        let locked = NSAttributedString(string: "Locked by NotchLock", attributes: [.font: lf, .foregroundColor: NSColor(white: 0.92, alpha: fadeIn)])
        locked.draw(at: CGPoint(x: cx - locked.size().width / 2, y: 232))
        let pill = CGRect(x: cx - 150, y: 180, width: 300, height: 40)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: Double(fadeIn) * 0.12))
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 20, cornerHeight: 20, transform: nil)); ctx.fillPath()
        let hf = NSFont.systemFont(ofSize: 15, weight: .regular)
        let hint = NSAttributedString(string: "Enter Password", attributes: [.font: hf, .foregroundColor: NSColor(white: 0.7, alpha: fadeIn)])
        hint.draw(at: CGPoint(x: cx - hint.size().width / 2, y: pill.minY + 11))
        ctx.restoreGState()
    }

    private static func drawPadlock(_ ctx: CGContext, center c: CGPoint, alpha: CGFloat) {
        ctx.saveGState(); ctx.translateBy(x: c.x, y: c.y)
        ctx.setStrokeColor(CGColor(srgbRed: 0.9, green: 0.92, blue: 1, alpha: Double(alpha))); ctx.setLineWidth(10)
        ctx.addArc(center: CGPoint(x: 0, y: 18), radius: 22, startAngle: 0, endAngle: .pi, clockwise: false)
        ctx.move(to: CGPoint(x: -22, y: 18)); ctx.addLine(to: CGPoint(x: -22, y: 4))
        ctx.move(to: CGPoint(x: 22, y: 18)); ctx.addLine(to: CGPoint(x: 22, y: 4)); ctx.strokePath()
        let body = CGRect(x: -34, y: -40, width: 68, height: 52)
        if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [CGColor(srgbRed: 0.95, green: 0.80, blue: 0.42, alpha: Double(alpha)),
                                       CGColor(srgbRed: 0.82, green: 0.62, blue: 0.24, alpha: Double(alpha))] as CFArray, locations: [0, 1]) {
            ctx.saveGState(); ctx.addPath(CGPath(roundedRect: body, cornerWidth: 12, cornerHeight: 12, transform: nil)); ctx.clip()
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: []); ctx.restoreGState()
        }
        ctx.setFillColor(CGColor(srgbRed: 0.15, green: 0.10, blue: 0.03, alpha: Double(alpha)))
        ctx.fillEllipse(in: CGRect(x: -7, y: -18, width: 14, height: 14))
        ctx.beginPath(); ctx.move(to: CGPoint(x: -4, y: -14)); ctx.addLine(to: CGPoint(x: 4, y: -14))
        ctx.addLine(to: CGPoint(x: 7, y: -32)); ctx.addLine(to: CGPoint(x: -7, y: -32)); ctx.closePath(); ctx.fillPath()
        ctx.restoreGState()
    }

    private static func drawVignette(_ ctx: CGContext) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        if let g = CGGradient(colorsSpace: space, colors: [CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0),
                                                           CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28)] as CFArray, locations: [0.6, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: CGFloat(H) / 2), startRadius: 0,
                                   endCenter: CGPoint(x: cx, y: CGFloat(H) / 2), endRadius: CGFloat(W) * 0.62, options: [])
        }
    }

    // MARK: - Helpers

    private static func smooth(_ u: Double) -> Double { let e = min(1, max(0, u)); return e * e * (3 - 2 * e) }
    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * CGFloat(u), y: a.y + (b.y - a.y) * CGFloat(u))
    }

    private static func drawText(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) {
        guard !s.isEmpty, size > 0 else { return }
        NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]).draw(at: p)
    }

    private static func bottomRoundedPath(_ r: CGRect, radius: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + radius))
        p.addQuadCurve(to: CGPoint(x: r.minX + radius, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - radius, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + radius), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.closeSubpath()
        return p
    }

    private static func appendFrame(_ img: CGImage, adaptor: AVAssetWriterInputPixelBufferAdaptor, input: AVAssetWriterInput, frame: Int) {
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
        CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
    }
}
