// swift-tools-version: 5.9
// macOS System Audio Recording CLI using Core Audio Tap APIs

import PackageDescription

let package = Package(
    name: "AudioRecorderCLI",
    platforms: [
        .macOS(.v14)  // Requires macOS 14.4+ for Core Audio Tap APIs
    ],
    products: [
        .executable(
            name: "AudioRecorderCLI",
            targets: ["AudioRecorderCLI"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "AudioRecorderCLI",
            dependencies: [],
            path: "Sources"
        ),
    ]
)
