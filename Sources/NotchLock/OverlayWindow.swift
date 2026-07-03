import AppKit

/// A transparent panel that floats above the menu bar so the pull-cord can be
/// drawn around the notch. It is click-through EVERYWHERE except the small,
/// moving bead region: the content view's `hitTest` returns the view only over
/// the visible bead (so the hand cursor sticks and a grab is captured), and
/// `nil` everywhere else, letting all other clicks pass straight through.
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
        // The window CAN receive events, but the content view's hitTest only
        // claims the tiny bead circle — everywhere else passes through.
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
