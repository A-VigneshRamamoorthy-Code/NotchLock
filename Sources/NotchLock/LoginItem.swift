import Foundation

/// Makes NotchLock survive a reboot by installing a per-user LaunchAgent
/// (`~/Library/LaunchAgents/com.notchlock.NotchLock.plist`) with `RunAtLoad`.
///
/// The plist is only *written* (not bootstrapped) while the app is already
/// running, so we never spawn a duplicate this session — launchd starts it at
/// the next login/reboot. It self-heals: if the recorded path is stale (e.g. the
/// app was moved to /Applications) the plist is rewritten on launch.
enum LoginItem {
    static let label = "com.notchlock.NotchLock"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// The running executable inside the .app bundle.
    static var executablePath: String {
        Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
    }

    static var isEnabled: Bool {
        guard let prog = recordedProgram() else { return false }
        return prog == executablePath
    }

    private static func recordedProgram() -> String? {
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any] else { return nil }
        return dict["Program"] as? String
    }

    /// Ensure the LaunchAgent exists and points at the current executable.
    @discardableResult
    static func enable() -> Bool {
        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "Label": label,
            "Program": executablePath,
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                             format: .xml, options: 0) else { return false }
        do { try data.write(to: plistURL) } catch { return false }
        return true
    }

    /// Remove the LaunchAgent so the app no longer starts at login.
    static func disable() {
        let uid = getuid()
        _ = launchctl(["bootout", "gui/\(uid)/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    /// Called at launch: install if missing, or repair a stale path.
    static func synchronize() {
        if !isEnabled { _ = enable() }
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { return -1 }
    }
}
