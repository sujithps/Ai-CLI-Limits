// swift-tools-version:5.9
// This manifest exists for the tests. The app itself is built by build.sh,
// because Swift Package Manager does not produce a .app bundle.
import PackageDescription

let package = Package(
    name: "AICLILimits",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AICLILimits", path: "Sources", exclude: ["main.swift"]),
        .testTarget(name: "AICLILimitsTests", dependencies: ["AICLILimits"], path: "Tests"),
    ]
)
