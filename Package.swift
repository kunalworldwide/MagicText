// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MagicText",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MagicText",
            dependencies: ["MagicTextCore"],
            path: "Sources/MagicText"
        ),
        .target(
            name: "MagicTextCore",
            path: "Sources/MagicTextCore"
        ),
        .testTarget(
            name: "MagicTextCoreTests",
            dependencies: ["MagicTextCore"],
            path: "Sources/MagicTextCoreTests"
        ),
    ]
)
