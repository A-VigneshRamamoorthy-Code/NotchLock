import AppKit

/// A transparent panel that floats above the menu bar so the pull-cord can be
/// drawn around the notch. It is **click-through by default** (`ignoresMouseEvents
/// = true`) so it never blocks the apps underneath. The controller flips it
/// interactive for the brief moments the cursor is directly over the small bead
/// (so it can be grabbed), then flips it back — see `OverlayController`.
final class OverlayWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        // Sit just above the menu bar so we can draw around the notch.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        // Click-through by default: never intercept mouse events unless the
        // controller explicitly enables it while the cursor is over the bead.
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
