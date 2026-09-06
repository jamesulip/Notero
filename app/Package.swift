// swift-tools-version: 6.2
import PackageDescription

// Four layers, each buildable and testable without the one above it.
//
//   TranscriberCore    pure logic. No AV, no CoreML, no UI, no models.
//   TranscriberStore   SwiftData schema + queries. No inference.
//   TranscriberEngine  audio I/O and the ASR/VAD/diarization backends.
//   TranscriberFlow    the app's decisions with no window: the job coordinator,
//                      the display status of a recording, the stop plan.
//   Transcriber        the SwiftUI app.
//
// The split is what keeps the commit policy, the merger and the exporters
// testable on a machine with no microphone and no 1.6 GB of weights.
let package = Package(
    name: "Transcriber",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Transcriber", targets: ["Transcriber"]),
        // Headless runner over the same pipeline: verification, eval and
        // benchmarking without a window or a microphone.
        .executable(name: "transcribe", targets: ["TranscriberCLI"]),
        .library(name: "TranscriberCore", targets: ["TranscriberCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.0"),
        // Silero VAD and pyannote diarization as CoreML, ANE-resident.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.6"),
    ],
    targets: [
        .target(
            name: "TranscriberCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "TranscriberStore",
            dependencies: ["TranscriberCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "TranscriberEngine",
            dependencies: [
                "TranscriberCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "TranscriberFlow",
            dependencies: ["TranscriberCore", "TranscriberStore", "TranscriberEngine"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                // The same isolation as the app: what lives here drives the
                // views and is observed by them.
                .defaultIsolation(MainActor.self),
            ]
        ),
        .executableTarget(
            name: "Transcriber",
            dependencies: ["TranscriberCore", "TranscriberStore", "TranscriberEngine", "TranscriberFlow"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                // SwiftUI views, @Observable app state and SwiftData contexts are
                // all main-actor work; declaring it once beats annotating every type.
                .defaultIsolation(MainActor.self),
            ]
        ),
        .executableTarget(
            name: "TranscriberCLI",
            dependencies: ["TranscriberCore", "TranscriberEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TranscriberCoreTests",
            dependencies: ["TranscriberCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TranscriberEngineTests",
            dependencies: ["TranscriberEngine", "TranscriberCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TranscriberStoreTests",
            dependencies: ["TranscriberStore", "TranscriberCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TranscriberFlowTests",
            dependencies: ["TranscriberFlow", "TranscriberCore", "TranscriberStore", "TranscriberEngine"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
