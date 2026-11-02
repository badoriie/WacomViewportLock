// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WacomViewportLock",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WacomViewportLock",
            path: "Sources/WacomViewportLock"
        ),
        .testTarget(
            name: "WacomViewportLockTests",
            dependencies: ["WacomViewportLock"],
            path: "Tests/WacomViewportLockTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
