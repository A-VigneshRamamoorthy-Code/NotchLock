import AppKit

let app = NSApplication.shared

// Hidden preview modes: render PNGs and exit (headless visual verification, no
// window server needed).
if let idx = CommandLine.arguments.firstIndex(of: "--render") {
    let outDir = CommandLine.arguments.indices.contains(idx + 1)
        ? CommandLine.arguments[idx + 1] : NSTemporaryDirectory() + "notchlock-preview"
    PreviewRenderer.renderAll(to: outDir)
    exit(0)
}
if let idx = CommandLine.arguments.firstIndex(of: "--contact") {
    let outDir = CommandLine.arguments.indices.contains(idx + 1)
        ? CommandLine.arguments[idx + 1] : NSTemporaryDirectory() + "notchlock-contact"
    PreviewRenderer.renderContact(to: outDir)
    exit(0)
}
if let idx = CommandLine.arguments.firstIndex(of: "--appicon") {
    let outPath = CommandLine.arguments.indices.contains(idx + 1)
        ? CommandLine.arguments[idx + 1] : NSTemporaryDirectory() + "NotchLockIcon.png"
    let ok = PreviewRenderer.renderAppIcon(to: outPath)
    exit(ok ? 0 : 1)
}
if let idx = CommandLine.arguments.firstIndex(of: "--styles") {
    let outPath = CommandLine.arguments.indices.contains(idx + 1)
        ? CommandLine.arguments[idx + 1] : NSTemporaryDirectory() + "notchlock-styles.png"
    let ok = PreviewRenderer.renderStyles(to: outPath)
    exit(ok ? 0 : 1)
}
if let idx = CommandLine.arguments.firstIndex(of: "--demo") {
    let outDir = CommandLine.arguments.indices.contains(idx + 1)
        ? CommandLine.arguments[idx + 1] : NSTemporaryDirectory() + "notchlock-demo"
    DemoRecorder.record(to: outDir)
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
