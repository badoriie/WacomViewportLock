// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WacomViewportLock",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "WacomViewportLock",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/WacomViewportLock",
            // Sparkle.framework is embedded in Contents/Frameworks by build_app.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "WacomViewportLockTests",
            dependencies: ["WacomViewportLock"],
            path: "Tests/WacomViewportLockTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
