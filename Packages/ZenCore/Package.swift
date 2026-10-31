// swift-tools-version: 5.9
import PackageDescription

// ZenCore holds the platform-independent rules (nudges, weekly summary, habit tracker)
// and the App Group store shared by the app and its Screen Time extension.
// It only depends on Foundation, so `swift test` runs on macOS and Linux.
let package = Package(
    name: "ZenCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ZenCore", targets: ["ZenCore"])
    ],
    targets: [
        .target(name: "ZenCore"),
        .testTarget(name: "ZenCoreTests", dependencies: ["ZenCore"])
    ]
)
