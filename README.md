# NotchLock 🔒

A tiny brass **pull-cord hangs from your MacBook notch** — just like the pull
chain on an old table lamp. Move your cursor up to the notch and the cord drops
into view, swinging on real drop physics. **Grab the bead, pull down, and let
go**: it stretches, snaps back and swings… and a couple of seconds later your
Mac **locks itself with a satisfying click**.

It's a native macOS menu-bar‑less agent: **no Dock icon, no status‑bar icon**,
≈**0 % CPU** when idle, and it **starts again automatically after a reboot**.

> Pull the light-cord to turn the lights off. 💡→🌙

---

## What it does

- **Peeks on approach** — the cord stays tucked in the notch until your cursor
  comes near, then drops out with gravity.
- **Real drop physics** — a Verlet rope pinned at the notch hangs straight and
  swings like a pendulum.
- **Grab · pull · release** — grab the bead, pull it down (the cord *stretches*
  toward your hand, clamped so it can't be yanked off), release and it recoils
  up and swings, exactly like a lamp pull‑chain.
- **Pull to lock** — pull past the threshold and, a few seconds later, NotchLock
  **locks your screen** with a lock sound (a lighter "click" plays when you grab,
  and a chime as it locks).
- **Invisible & idle‑free** — no Dock icon, no menu‑bar icon; the overlay is
  fully click‑through so it never blocks anything underneath. The animation loop
  sleeps when the cord is still → **0 % CPU**.
- **Survives reboots** — installs a per‑user LaunchAgent (`RunAtLoad`) so it
  comes back after you restart or log in again.

Right‑click the notch for the menu: **Lock Screen Now**, **Launch at Login**
(toggle), and **Quit**.

---

## Install (DMG)

1. Download / open **`NotchLock.dmg`**.
2. Drag **NotchLock** onto **Applications**.
3. Launch it. Because it's ad‑hoc signed (not notarized), the first time you may
   need to **right‑click → Open** and confirm.
4. Move your cursor to the notch, grab the cord and pull. ✨

On first launch NotchLock registers itself to **start automatically at login**
(turn this off any time from the right‑click menu).

> **Locking dependency:** NotchLock locks via the same system call macOS uses for
> *Lock Screen*. If that's ever unavailable it falls back to sleeping the display,
> which locks when *"Require password after sleep / screen saver begins"* is
> enabled in **System Settings → Lock Screen**.

---

## Build from source

Requires only the **Command Line Tools** (no Xcode) on Apple Silicon.

```bash
swift run notchlock-selftest      # run the headless physics/logic tests
./scripts/build_app.sh release    # → build/NotchLock.app
./scripts/make_dmg.sh             # → NotchLock.dmg (drag-to-install)
./scripts/install.sh              # copy to /Applications + launch (+ login item)
```

Preview the art & motion headlessly (writes PNGs, no GUI needed):

```bash
swift run NotchLock --render  /tmp/nl-pose      # hanging + armed poses
swift run NotchLock --contact /tmp/nl-contact   # pull → release → swing sheet
swift run NotchLock --appicon /tmp/nl-icon.png  # the app icon
```

Handy env vars for testing (all inert by default):

| Variable | Effect |
|----------|--------|
| `NOTCHLOCK_DRYRUN=1` | Log instead of actually locking the screen. |
| `NOTCHLOCK_DEBUG=1` | Log grab attempts and the bead position. |
| `NOTCHLOCK_SELFDRIVE=1` | Run an in‑process pull→lock integration test. |

---

## How it works

Pure simulation/drawing is split from the AppKit shell so the "brains" are
unit‑testable headlessly:

```
Sources/
  NotchLockCore/          # PURE (no AppKit): testable + every pixel drawn here
    NotchGeometry.swift    #   notch rect + anchor from NSScreen data
    Spring.swift           #   damped spring (reveal / tuck)
    ChainStyle.swift       #   all the tuning + palette
    ChainEngine.swift      #   Verlet pull-cord: drop physics, grab/drag/release,
                           #     springy stretch, fire-once lock threshold
    ChainRenderer.swift    #   tapered brass cord + bead + app icon (CoreGraphics)
  NotchLock/              # AppKit shell
    main.swift             #   entry (+ hidden --render/--contact/--appicon modes)
    AppDelegate.swift      #   monitors, drag state machine, menu, lock sequence
    OverlayWindow.swift    #   transparent, click-through NSPanel above the menu bar
    OverlayController.swift#   maps the global cursor into the cord's space
    ChainView.swift        #   CADisplayLink loop (pauses at rest → 0% CPU)
    MouseTracker.swift     #   global + local NSEvent monitors (no permissions)
    LockController.swift    #   SACLockScreenImmediate (+ pmset fallback) + sounds
    LoginItem.swift        #   LaunchAgent install/repair (reboot survival)
  notchlock-selftest/     # plain executable assertion harness (CLT has no XCTest)
scripts/                  # build_app.sh · make_dmg.sh · install.sh
```

The cord is a rigid Verlet rope pinned at the notch (so it hangs and swings under
gravity); revealing/hiding slides the pinned anchor above/below the top edge, and
the rope's **length** is a spring that stretches to your hand while pulled and
snaps back on release — giving the lamp‑cord recoil. Grabs/pulls are detected via
non‑consuming global `NSEvent` monitors, so the overlay never blocks your clicks.

---

## Notes

- Apple Silicon, macOS 14+.
- Ad‑hoc signed (not notarized) → first‑launch right‑click → Open.
- Works on Macs **without** a notch too (falls back to a top‑centre region).
