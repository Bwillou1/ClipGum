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
        // Pinned to the Swift 5.9/5.10-era APIs inspected for this implementation.
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.25.6"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "2.25.9"),
        // Re-exports llama.cpp b10549's prebuilt XCFramework; ClipGum owns the
        // bounded actor/C-API wrapper rather than depending on a high-level client.
        .package(
            url: "https://github.com/mattt/llama.swift",
            revision: "018619bf56f92cc85286150611609f456813826f"
        )
    ],
    targets: [
        .executableTarget(
            name: "ClipGum",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "LlamaSwift", package: "llama.swift")
            ],
            path: "Sources/ClipGum",
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
