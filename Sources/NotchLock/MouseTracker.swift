import AppKit

/// Watches global + local mouse events (event-driven, no polling) and reports
/// them in global screen coordinates. Global monitors OBSERVE events without
/// consuming them, so grabbing the bead never blocks the app underneath. Mouse
/// monitors require no special permission.
final class MouseTracker {
    var onMove: ((CGPoint) -> Void)?
    var onLeftDown: ((CGPoint) -> Void)?
    var onLeftDrag: ((CGPoint) -> Void)?
    var onLeftUp: ((CGPoint) -> Void)?
    /// Fired on a right-click (or ctrl-click). Does not consume the event.
    var onContextClick: ((CGPoint) -> Void)?

    private var monitors: [Any] = []

    func start() {
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        addBoth(moveMask) { [weak self] in
            self?.onMove?(NSEvent.mouseLocation)
            if $0.type == .leftMouseDragged { self?.onLeftDrag?(NSEvent.mouseLocation) }
        }
        addBoth([.leftMouseDown]) { [weak self] _ in self?.onLeftDown?(NSEvent.mouseLocation) }
        addBoth([.leftMouseUp]) { [weak self] _ in self?.onLeftUp?(NSEvent.mouseLocation) }
        addBoth([.rightMouseUp]) { [weak self] _ in self?.onContextClick?(NSEvent.mouseLocation) }
    }

    func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
    }

    private func addBoth(_ mask: NSEvent.EventTypeMask, _ handler: @escaping (NSEvent) -> Void) {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { e in
            handler(e); return e
        }) { monitors.append(m) }
    }

    deinit { stop() }
}
