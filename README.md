<div align="center">

<img src="assets/icon.png" width="132" alt="NotchLock icon" />

# NotchLock

### Pull the cord. Lock your Mac. 🔒

**A brass pull‑string hangs from your MacBook notch — like the chain on an old
table lamp. Give it a tug and, a beat later, your Mac locks itself with a
satisfying click.**

![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple&logoColor=white)
![Apple silicon](https://img.shields.io/badge/Apple%20silicon-native-black?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![Build](https://img.shields.io/badge/build-SwiftPM%20·%20no%20Xcode-blue)
![Idle CPU](https://img.shields.io/badge/idle%20CPU-0%25-brightgreen)
![Dock icon](https://img.shields.io/badge/Dock%20icon-none-lightgrey)
![Size](https://img.shields.io/badge/download-~600%20KB-success)

<br/>

<img src="assets/notchlock-demo.gif" width="760" alt="NotchLock demo — a cord drops from the notch, you pull it, and the Mac locks" />

<sub>▶ <a href="assets/notchlock-demo.mp4"><b>Watch the HD video</b></a> · every pixel is drawn by the app's own engine</sub>

</div>

---

## ✨ The idea

Locking your Mac should feel as good as *chunk*‑ing off a lamp for the night.

Slide your cursor up to the notch and a little **pull‑cord drops out** on real
drop physics. Grab the bead, **pull it down** — the cord stretches toward your
hand and glows red once it's armed — then **let go**. It snaps back and swings
like a real lamp chain… and a couple of seconds later your **Mac locks**, with a
soft *click* as you grab and a chime as it locks.

No Dock icon. No menu‑bar icon. **0 % CPU** when it's just hanging there. And it
**comes back after a reboot**.

---

## 🎬 How to use it

<table>
<tr>
<td width="33%" valign="top">

### 1 · Approach
Move your cursor up to the **notch**. The cord drops into view and hangs,
swaying gently under gravity.

</td>
<td width="33%" valign="top">

### 2 · Pull
**Grab the bead** and drag it **down**. The cord stretches; past the threshold it
turns **red — armed**.

</td>
<td width="33%" valign="top">

### 3 · Lock
**Let go.** It recoils and swings, then a beat later your **Mac locks** with a
sound. Lights out. 🌙

</td>
</tr>
</table>

> Prefer the keyboard‑free classic? Right‑click the notch for **Lock Screen Now**.

---

## 🧩 Features

|  |  |
|---|---|
| 🪝 **Lamp‑cord physics** | A pinned Verlet rope drops, hangs and swings under real gravity — grab, stretch, release, recoil. |
| 🔒 **Pull to lock** | Pull past the threshold and NotchLock locks your screen (via the same call as macOS *Lock Screen*), with grab + lock sounds. |
| 🫥 **Truly invisible** | Agent app: **no Dock icon, no status‑bar icon**. A fully click‑through overlay — it never blocks a single click underneath. |
| 🪫 **0 % idle CPU** | The animation loop sleeps the instant the cord is still. Nothing moving, nothing burning. |
| 🔁 **Survives reboot** | Registers a `RunAtLoad` LaunchAgent (self‑healing) so it's back after every restart or login. |
| 🖱️ **Zero permissions** | Uses global event monitors — no Accessibility or Screen‑Recording grants required. |
| 🎨 **Drawn in code** | Cord, bead, icon — all CoreGraphics. No asset files, ~600 KB app. |
| 🛠️ **No Xcode** | Pure SwiftPM. Builds with the Command Line Tools and hand‑assembles the `.app`. |

---

## 📥 Install

1. Download **[`NotchLock.dmg`](NotchLock.dmg)**.
2. Drag **NotchLock** onto **Applications**.
3. Launch it. It's ad‑hoc signed (not notarized), so the first time
   **right‑click → Open** and confirm.
4. Slide to the notch, grab the cord, and pull. ✨

On first launch NotchLock sets itself to **start at login** — toggle that any time
from the right‑click menu.

> **Note on locking:** NotchLock locks using the same system routine as macOS
> *Lock Screen*. If that's ever unavailable it falls back to sleeping the display,
> which locks when *“Require password after sleep / screen saver begins”* is on in
> **System Settings → Lock Screen**.

---

## 🔧 Build from source

Needs only the **Command Line Tools** (no Xcode) on Apple silicon.

```bash
swift run notchlock-selftest      # headless physics/logic tests (35 checks)
./scripts/build_app.sh release    # → build/NotchLock.app
./scripts/make_dmg.sh             # → NotchLock.dmg (drag-to-install)
./scripts/install.sh              # copy to /Applications, launch, add login item
```

Preview the art & motion headlessly — no GUI, no Screen‑Recording permission:

```bash
swift run NotchLock --render  /tmp/pose      # hanging + armed poses
swift run NotchLock --contact /tmp/contact   # pull → release → swing contact sheet
swift run NotchLock --demo    /tmp/demo      # the full product demo (mp4 + frames)
swift run NotchLock --appicon /tmp/icon.png  # the app icon
```

Handy env vars (all inert by default):

| Variable | Effect |
|----------|--------|
| `NOTCHLOCK_DRYRUN=1` | Log instead of actually locking the screen. |
| `NOTCHLOCK_DEBUG=1` | Log grab attempts and the bead position. |
| `NOTCHLOCK_SELFDRIVE=1` | Run an in‑process pull→lock integration test. |

---

## 🪄 Under the notch — how it works

Pure simulation/drawing is split from the AppKit shell so the “brains” are
unit‑testable headlessly:

```
Sources/
  NotchLockCore/           # PURE (no AppKit): testable + every pixel drawn here
    NotchGeometry.swift      #   notch rect + anchor from NSScreen data
    Spring.swift             #   damped spring (reveal / tuck)
    ChainStyle.swift         #   all the tuning + palette
    ChainEngine.swift        #   Verlet pull-cord: drop physics, grab/drag/release,
                             #     springy stretch, fire-once lock threshold
    ChainRenderer.swift      #   tapered brass cord + bead + app icon (CoreGraphics)
  NotchLock/               # AppKit shell
    main.swift               #   entry (+ hidden --render/--contact/--demo/--appicon)
    AppDelegate.swift        #   monitors, drag state machine, menu, lock sequence
    OverlayWindow.swift      #   transparent, click-through NSPanel above the menu bar
    OverlayController.swift  #   maps the global cursor into the cord's space
    ChainView.swift          #   CADisplayLink loop (pauses at rest → 0% CPU)
    MouseTracker.swift       #   global + local NSEvent monitors (no permissions)
    LockController.swift     #   SACLockScreenImmediate (+ pmset fallback) + sounds
    LoginItem.swift          #   LaunchAgent install/repair (reboot survival)
    DemoRecorder.swift       #   the AVFoundation product-demo recorder
  notchlock-selftest/      # plain executable assertion harness (CLT has no XCTest)
scripts/                   # build_app.sh · make_dmg.sh · install.sh
```

The cord is a **rigid Verlet rope** pinned at the notch — so it hangs and swings
like a pendulum under gravity. Showing/hiding slides the pinned anchor above or
below the top edge (it never collapses), and the rope's **length is a spring**
that stretches to your hand while pulled and snaps back on release — that's the
lamp‑cord recoil. Grabs and pulls are read from **non‑consuming global `NSEvent`
monitors**, so the decorative overlay never eats your clicks.

The demo above isn't a screen capture — it's rendered by the **same core the live
app uses** (`--demo`), so what you see is exactly what runs.

---

## 📝 Notes

- Apple silicon, macOS 14+.
- Ad‑hoc signed (not notarized) → first‑launch right‑click → **Open**.
- Works on Macs **without** a notch too (falls back to a top‑centre region).

<div align="center"><sub>Made with 🤎 and CoreGraphics · pull the cord.</sub></div>
