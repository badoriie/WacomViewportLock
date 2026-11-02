// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "WacomViewportLock",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WacomViewportLock",
            path: "Sources/WacomViewportLock"
        )
    ]
)
