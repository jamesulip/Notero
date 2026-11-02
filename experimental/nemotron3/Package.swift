// swift-tools-version: 6.2
//
// EXPERIMENTAL. Not part of the app and not built by `app/Package.swift`.
//
// An isolated speaker-diarization backend on NVIDIA Nemotron 3 Diarization,
// through FluidAudio's Core ML port. It is a separate package because the port
// needs FluidAudio 0.17.4 or later, and the app keeps FluidAudio on 0.15.x:
// docs/FINDINGS.md entry 20 records that 0.15.8 and 0.18.0 deleted a model cache
// without a revision marker when the network was denied. Moving the app's pin is a
// separate decision with its own offline test; this package does not make it.
//
// The backend conforms to the app's own `SpeakerDiarizing` protocol: the targets
// `TranscriberCore` and `EngineSeams` are symbolic links to the app's source files
// (`app/Sources/TranscriberCore` and `app/Sources/TranscriberEngine/Protocols.swift`),
// so a change to the protocol breaks this build too.
//
// See docs/DIARIZATION.md.

import PackageDescription

let package = Package(
    name: "Nemotron3Experiment",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "nemodiarbench", targets: ["nemodiarbench"]),
    ],
    dependencies: [
        // Exact: an experiment is only comparable to itself at one version.
        .package(url: "https://github.com/FluidInference/FluidAudio.git",
                 exact: "0.18.0", traits: ["Diarizer"]),
    ],
    targets: [
        .target(name: "TranscriberCore",
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "EngineSeams",
                dependencies: ["TranscriberCore"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "Nemotron3Backend",
                dependencies: ["TranscriberCore", "EngineSeams",
                               .product(name: "FluidAudio", package: "FluidAudio")],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(name: "nemodiarbench",
                          dependencies: ["TranscriberCore", "EngineSeams", "Nemotron3Backend"],
                          swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "Nemotron3BackendTests",
                    dependencies: ["Nemotron3Backend", "EngineSeams", "TranscriberCore"],
                    swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
