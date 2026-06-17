// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OpenQuack",
    platforms: [
        // 13 is WhisperKit's minimum; the GUI app will set its own (likely 15) when added.
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "OpenQuackPlatform",
            targets: ["OpenQuackPlatform"]
        ),
        .library(
            name: "OpenQuackKit",
            targets: ["OpenQuackKit"]
        ),
        .executable(
            name: "openquack-bench",
            targets: ["OpenQuackBench"]
        ),
        .executable(
            name: "openquack-polish-bench",
            targets: ["OpenQuackPolishBench"]
        ),
        .executable(
            name: "openquack-bias-bench",
            targets: ["OpenQuackBiasBench"]
        ),
        .executable(
            name: "openquack-stream-bench",
            targets: ["OpenQuackStreamBench"]
        ),
        .executable(
            name: "openquack-cli",
            targets: ["OpenQuackCLI"]
        ),
        .executable(
            name: "openquack",
            targets: ["OpenQuackApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.18.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.4.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.4.0"),
        // SPEC-026 — Sparkle 2.x for in-app updates on the DMG path.
        // Kept off OpenQuackKit (kit stays Sparkle-free); linked only into
        // OpenQuackApp. `from: "2.6.0"` floats up through 2.x; do not pin a
        // branch.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
        // SPEC-007 — in-process llama.cpp polish engine. Thin binding: a
        // binaryTarget over the official llama.cpp xcframework, tracked daily.
        // We write the inference loop ourselves (see LlamaCppPolishEngine).
        .package(url: "https://github.com/mattt/llama.swift", .upToNextMajor(from: "2.9488.0")),
    ],
    targets: [
        .target(
            name: "OpenQuackPlatform",
            dependencies: [],
            path: "Sources/OpenQuackPlatform"
        ),
        // Tiny Objective-C shim: lets Swift catch the NSExceptions that
        // AVAudioEngine.installTap raises on format mismatches (otherwise an
        // uncatchable SIGABRT). See OQObjCSupport.h.
        .target(
            name: "OQObjCSupport",
            path: "Sources/OQObjCSupport"
        ),
        .target(
            name: "OpenQuackStreaming",
            dependencies: [
                "OpenQuackPlatform",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            path: "Sources/OpenQuackStreaming"
        ),
        .target(
            name: "OpenQuackKit",
            dependencies: [
                "OpenQuackPlatform",
                "OpenQuackStreaming",
                "OQObjCSupport",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "LlamaSwift", package: "llama.swift"),
            ],
            path: "Sources/OpenQuackKit"
        ),
        .executableTarget(
            name: "OpenQuackBench",
            dependencies: [
                "OpenQuackKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/OpenQuackBench"
        ),
        .executableTarget(
            name: "OpenQuackPolishBench",
            dependencies: [
                "OpenQuackPlatform",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/OpenQuackPolishBench"
        ),
        .executableTarget(
            name: "OpenQuackBiasBench",
            dependencies: [
                "OpenQuackPlatform",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/OpenQuackBiasBench"
        ),
        .executableTarget(
            name: "OpenQuackStreamBench",
            dependencies: [
                "OpenQuackPlatform",
                "OpenQuackStreaming",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/OpenQuackStreamBench"
        ),
        .executableTarget(
            name: "OpenQuackCLI",
            dependencies: [
                "OpenQuackKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/OpenQuackCLI"
        ),
        .executableTarget(
            name: "OpenQuackApp",
            dependencies: [
                "OpenQuackKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/OpenQuackApp",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "OpenQuackKitTests",
            dependencies: ["OpenQuackKit"],
            path: "Tests/OpenQuackKitTests"
        ),
    ]
)
