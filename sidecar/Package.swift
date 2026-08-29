// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "asrd",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "asrd",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit")]
        )
    ]
)
