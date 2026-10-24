// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClipGum",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ClipGum", targets: ["ClipGum"])
    ],
    dependencies: [
        // Pinned to the inspected macOS 14-compatible LM-only package layout.
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "2.31.3"),
        // Re-exports llama.cpp b10549's prebuilt XCFramework; ClipGum owns the
        // bounded actor/C-API wrapper rather than depending on a high-level client.
        .package(
            url: "https://github.com/mattt/llama.swift",
            revision: "018619bf56f92cc85286150611609f456813826f"
        ),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "ClipGum",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "LlamaSwift", package: "llama.swift"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/ClipGum",
            resources: [
                .process("UI/Settings/Licenses/Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "ClipGumTests",
            dependencies: ["ClipGum"],
            path: "Tests/ClipGumTests"
        )
    ]
)
