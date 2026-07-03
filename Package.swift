// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchLock",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchLock", targets: ["NotchLock"]),
        .library(name: "NotchLockCore", targets: ["NotchLockCore"]),
    ],
    targets: [
        // Pure simulation + drawing — no AppKit, so it runs headless and testable.
        .target(name: "NotchLockCore"),
        // AppKit shell (overlay window, monitors, menu, lock action).
        .executableTarget(
            name: "NotchLock",
            dependencies: ["NotchLockCore"]
        ),
        // Plain executable test harness (Command Line Tools have no XCTest).
        .executableTarget(
            name: "notchlock-selftest",
            dependencies: ["NotchLockCore"]
        ),
    ]
)
