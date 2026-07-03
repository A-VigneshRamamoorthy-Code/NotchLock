import AppKit
import NotchLockCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: OverlayController?
    private let tracker = MouseTracker()
    private var cordStyle: CordStyle = .brass
    private var style: ChainStyle { cordStyle.style }
    private let defaultsKey = "NotchLock.cordStyle"

    private var dragging = false
    private var lockPending = false
    /// Set NOTCHLOCK_DRYRUN=1 to log instead of actually locking (for testing).
    private let dryRun = ProcessInfo.processInfo.environment["NOTCHLOCK_DRYRUN"] != nil
    /// Set NOTCHLOCK_DEBUG=1 to log grab attempts / bead position.
    private let debug = ProcessInfo.processInfo.environment["NOTCHLOCK_DEBUG"] != nil
    /// Set NOTCHLOCK_SELFDRIVE=1 to run an in-process pull→lock integration test
    /// (drives the real controller/engine, bypassing only the OS mouse monitors,
    /// which can't be exercised synthetically without Accessibility permission).
    private let selfDrive = ProcessInfo.processInfo.environment["NOTCHLOCK_SELFDRIVE"] != nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enforce a single instance (a login-agent copy + a manual copy would
        // otherwise draw two cords).
        if let bid = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty { NSApp.terminate(nil); return }
        }

        NSApp.setActivationPolicy(.accessory)   // no Dock icon, no app menu

        // Restore the chosen cord look.
        if let raw = UserDefaults.standard.string(forKey: defaultsKey),
           let s = CordStyle(rawValue: raw) { cordStyle = s }

        // Survive reboots: install/repair the RunAtLoad LaunchAgent.
        LoginItem.synchronize()

        rebuildOverlay()

        tracker.onMove = { [weak self] p in self?.handleMove(p) }
        tracker.onLeftDown = { [weak self] p in self?.handleLeftDown(p) }
        tracker.onLeftDrag = { [weak self] p in self?.handleLeftDrag(p) }
        tracker.onLeftUp = { [weak self] p in self?.handleLeftUp(p) }
        tracker.onContextClick = { [weak self] p in self?.handleContextClick(p) }
        tracker.start()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        NSLog("NotchLock running%@. Move to the notch, grab the cord and pull to lock.",
              dryRun ? " [DRYRUN]" : "")

        if selfDrive { scheduleSelfDrive() }
    }

    // MARK: - In-process integration self-drive (testing only)

    /// Simulates a real grab → pull-past-threshold → release by calling the same
    /// handlers the mouse monitors call, using the cord's actual on-screen
    /// position. Proves the whole controller→engine→lock chain end to end.
    private func scheduleSelfDrive() {
        guard controller != nil else { return }
        let mode = (ProcessInfo.processInfo.environment["NOTCHLOCK_SELFDRIVE"] ?? "1").lowercased()
        if mode == "align" { runAlignProbe(); return }
        if mode == "interactive" { runInteractiveProbe(); return }
        runSelfDrive(cancel: mode == "cancel")
    }

    /// Click-through probe: the overlay must capture clicks ONLY while the cursor
    /// is over the bead, and be click-through (ignoresMouseEvents) everywhere else.
    private func runInteractiveProbe() {
        guard let c = controller else { return }
        // Engage first so the cord drops out, then hover the bead.
        handleMove(c.beadGlobalPosition())
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, let c = self.controller else { return }
            let beadG = c.beadGlobalPosition()
            self.handleMove(beadG)          // exactly on the bead
            let onBead = c.isInteractive
            NSLog("NotchLock[interactive] emergence=%.2f beadGlobal=%@ onBead=%@",
                  c.chainView.emergenceValue, NSStringFromPoint(beadG), onBead ? "true" : "false")
            // Move well away from the bead (down into the desktop/app area).
            let away = CGPoint(x: beadG.x + 260, y: beadG.y - 200)
            self.handleMove(away)
            let offBead = c.isInteractive
            NSLog("NotchLock[interactive] onBead=%@ offBead=%@ (want: true, false)",
                  onBead ? "true" : "false", offBead ? "true" : "false")
            NSLog("NotchLock[interactive] background clickable off-bead: %@", offBead ? "NO" : "YES")
        }
    }

    /// Issue #1 probe: feed off-centre cursors and log where the cord drops from.
    private func runAlignProbe() {
        guard let c = controller else { return }
        let zone = c.notchHotZone()
        let leftX = zone.minX + 6, rightX = zone.maxX - 6, y = zone.midY
        // Move far left, let it settle, log bead x; then far right.
        handleMove(CGPoint(x: leftX, y: y))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, let c = self.controller else { return }
            let bl = c.beadGlobalPosition().x
            NSLog("NotchLock[align] cursorX=%.0f (left)  beadX=%.0f", leftX, bl)
            self.handleMove(CGPoint(x: rightX, y: y))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let br = c.beadGlobalPosition().x
                NSLog("NotchLock[align] cursorX=%.0f (right) beadX=%.0f", rightX, br)
                NSLog("NotchLock[align] follows cursor: %@", br > bl + 40 ? "YES" : "NO")
            }
        }
    }

    private func runSelfDrive(cancel: Bool) {
        guard let controller else { return }
        let notch = controller.beadGlobalPosition()
        handleMove(notch)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in
            guard let self, let c = self.controller else { return }
            let bead = c.beadGlobalPosition()
            self.handleMove(bead)
            self.handleLeftDown(bead)
            let depth: CGFloat = 210
            let pullFrames = 26
            let holdFrames = 16
            for i in 1...(pullFrames + holdFrames) {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.04) {
                    let f = min(CGFloat(i) / CGFloat(pullFrames), 1)
                    let y = bead.y - depth * f
                    self.handleLeftDrag(CGPoint(x: bead.x, y: y))
                }
            }
            var t = Double(pullFrames + holdFrames) * 0.04
            if cancel {
                // Bring the hand back up near rest before releasing.
                let upFrames = 20
                for i in 1...upFrames {
                    DispatchQueue.main.asyncAfter(deadline: .now() + t + Double(i) * 0.04) {
                        let f = CGFloat(i) / CGFloat(upFrames)
                        let y = bead.y - depth * (1 - f)   // back toward rest
                        self.handleLeftDrag(CGPoint(x: bead.x, y: y))
                    }
                }
                t += Double(upFrames) * 0.04
                DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.1) {
                    self.handleLeftUp(CGPoint(x: bead.x, y: bead.y))
                    NSLog("NotchLock[selfdrive] CANCEL gesture complete (released near rest)")
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + t + 0.1) {
                    self.handleLeftUp(CGPoint(x: bead.x, y: bead.y - depth))
                    NSLog("NotchLock[selfdrive] FIRE gesture complete (released while pulled ≈ %.0f pt)", Double(depth))
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tracker.stop()
    }

    // MARK: - Overlay lifecycle

    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    }

    private func rebuildOverlay() {
        controller?.close()
        guard let screen = notchScreen() else { return }
        let c = OverlayController(screen: screen, style: style)
        c.show()
        controller = c
    }

    @objc private func screensChanged() { rebuildOverlay() }

    // MARK: - Mouse handling

    private func handleMove(_ p: CGPoint) {
        // Controller updates engagement, the drop position, the click-through
        // hotspot, and the hand cursor — all gated to the bead.
        controller?.handleMouseMoved(globalPoint: p)
    }

    private func handleLeftDown(_ p: CGPoint) {
        guard let controller else { return }
        let grabbed = controller.tryGrab(globalPoint: p)
        if debug {
            let bead = controller.beadGlobalPosition()
            NSLog("NotchLock[debug] leftDown at \(p) bead=\(bead) grab=\(grabbed)")
        }
        if grabbed {
            dragging = true
            NSCursor.closedHand.set()
            LockController.playSound("Tink")   // "grab" tick
        }
    }

    private func handleLeftDrag(_ p: CGPoint) {
        guard dragging else { return }
        controller?.drag(globalPoint: p)
    }

    private func handleLeftUp(_ p: CGPoint) {
        guard dragging, let controller else { return }
        dragging = false
        let fired = controller.release()
        if debug { NSLog("NotchLock[debug] release fired=\(fired)") }
        if fired { triggerLockSequence() }
    }

    /// Right-click near the notch opens the menu. The global monitor does not
    /// consume the click, so it never blocks the app underneath.
    private func handleContextClick(_ p: CGPoint) {
        guard controller?.isInNotchHotZone(globalPoint: p) == true else { return }
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.buildMenu().popUp(positioning: nil, at: p, in: nil)
        }
    }

    // MARK: - The pull → lock sequence

    private func triggerLockSequence() {
        guard !lockPending else { return }
        lockPending = true
        LockController.playSound("Submarine")   // the lock chime

        // Lock (almost) immediately — a tiny delay just lets the release recoil
        // begin and the sound start before the display cuts.
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, style.lockDelay)) { [weak self] in
            guard let self else { return }
            self.lockPending = false
            if self.dryRun {
                NSLog("NotchLock: [DRYRUN] would lock the screen now.")
            } else {
                LockController.lockScreen()
            }
        }
    }

    // MARK: - Menu (no status item; opened by right-clicking the notch)

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "NotchLock", action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(string: "NotchLock", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.labelColor,
        ])
        if let cg = ChainRenderer.icon(for: style, size: CGSize(width: 22, height: 30)) {
            header.image = NSImage(cgImage: cg, size: NSSize(width: 22, height: 30))
        }
        menu.addItem(header)

        let hint = NSMenuItem(title: "Pull the cord to lock", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        hint.attributedTitle = NSAttributedString(string: "Pull the cord to lock the screen", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        menu.addItem(hint)
        menu.addItem(.separator())

        // Style picker (like NotchPaw — pick your cord under the notch).
        let styleHeader = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        styleHeader.isEnabled = false
        styleHeader.attributedTitle = NSAttributedString(string: "Cord style", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        menu.addItem(styleHeader)

        let iconSize = NSSize(width: 26, height: 34)
        for s in CordStyle.allCases {
            let item = NSMenuItem(title: s.displayName, action: #selector(selectStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = s.rawValue
            item.attributedTitle = styleTitle(for: s)
            item.state = (s == cordStyle) ? .on : .off
            if let cg = ChainRenderer.icon(for: s.style, size: CGSize(width: iconSize.width, height: iconSize.height)) {
                item.image = NSImage(cgImage: cg, size: iconSize)
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let lockNow = NSMenuItem(title: "Lock Screen Now", action: #selector(lockNow), keyEquivalent: "l")
        lockNow.target = self
        menu.addItem(lockNow)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit NotchLock", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    /// Two-line styled menu title: bold name over a smaller grey tagline.
    private func styleTitle(for s: CordStyle) -> NSAttributedString {
        let str = NSMutableAttributedString(string: s.displayName, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        str.append(NSAttributedString(string: "\n" + s.tagline, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return str
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let s = CordStyle(rawValue: raw) else { return }
        cordStyle = s
        controller?.updateStyle(s.style)
        UserDefaults.standard.set(s.rawValue, forKey: defaultsKey)
        LockController.playSound("Tink")
    }

    @objc private func lockNow() {
        LockController.playSound("Submarine")
        if dryRun { NSLog("NotchLock: [DRYRUN] Lock Screen Now.") }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { LockController.lockScreen() } }
    }

    @objc private func toggleLogin() {
        if LoginItem.isEnabled { LoginItem.disable() } else { LoginItem.enable() }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
