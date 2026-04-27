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
            name: "OpenQuackKit",
            targets: ["OpenQuackKit"]
        ),
        .executable(
            name: "openquack-bench",
            targets: ["OpenQuackBench"]
        ),
        .executable(
            name: "openquack-cli",
            targets: ["OpenQuackCLI"]
        ),
        .executable(
            name: "openquack-app",
            targets: ["OpenQuackApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.18.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.4.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.4.0"),
    ],
    targets: [
        .target(
            name: "OpenQuackKit",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
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
            name: "OpenQuackCLI",
            dependencies: [
                "OpenQuackKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/OpenQuackCLI"
        ),
        .executableTarget(
            name: "OpenQuackApp",
            dependencies: ["OpenQuackKit"],
            path: "Sources/OpenQuackApp"
        ),
        .testTarget(
            name: "OpenQuackKitTests",
            dependencies: ["OpenQuackKit"],
            path: "Tests/OpenQuackKitTests"
        ),
    ]
)
