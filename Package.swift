// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MagicText",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Local model runtime (Apple MLX on Metal). Pinned — verified API surface.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "3.31.4"),
        // HF hub + tokenizer implementations required by MLXHuggingFace macros.
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "MagicText",
            dependencies: [
                "MagicTextCore",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
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
