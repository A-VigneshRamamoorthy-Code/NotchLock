import AppKit

/// Locks the screen and plays feedback sounds. Locking uses the private
/// `login.framework` (immediate, no permission prompt) with a display-sleep
/// fallback. Sounds use the built-in macOS system sounds.
enum LockController {
    private static var active: [NSSound] = []

    /// Play a named macOS system sound (e.g. "Pop", "Submarine"). Falls back to
    /// a beep. A strong reference is held until playback finishes.
    static func playSound(_ name: String) {
        let sound = NSSound(named: NSSound.Name(name)) ?? fileSound(name)
        guard let sound else { NSSound.beep(); return }
        active.append(sound)
        sound.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            active.removeAll { $0 === sound }
        }
    }

    private static func fileSound(_ name: String) -> NSSound? {
        let path = "/System/Library/Sounds/\(name).aiff"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSSound(contentsOfFile: path, byReference: true)
    }

    /// Lock the screen immediately.
    static func lockScreen() {
        if lockViaLoginFramework() { return }
        // Fallback: sleep the display. Locks if "require password after sleep /
        // screen saver begins" is enabled in System Settings → Lock Screen.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["displaysleepnow"]
        try? p.run()
    }

    /// Call `SACLockScreenImmediate()` from the private login framework — the
    /// same call the macOS "Lock Screen" menu uses. No permission required.
    private static func lockViaLoginFramework() -> Bool {
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        guard let handle = dlopen(path, RTLD_NOW) else { return false }
        defer { dlclose(handle) }
        guard let sym = dlsym(handle, "SACLockScreenImmediate") else { return false }
        typealias LockFn = @convention(c) () -> Int32
        let fn = unsafeBitCast(sym, to: LockFn.self)
        _ = fn()
        return true
    }
}
