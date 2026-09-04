import SwiftUI
import TranscriberCore
import TranscriberEngine
import TranscriberStore
import UniformTypeIdentifiers

/// Measures the tiers on this Mac, on audio the user chooses.
struct BenchmarkView: View {
    @Environment(AppState.self) private var state

    @State private var report: BenchmarkReport?
    @State private var running: Task<Void, Never>?
    @State private var stage = ""
    @State private var fraction: Double = 0
    @State private var picking = false
    @State private var clipName = ""
    @State private var tiers: Set<ModelTier> = [.fast, .balanced]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if running != nil {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(stage).font(.callout)
                            ProgressView(value: fraction)
                            Button("Stop") {
                                running?.cancel()
                                running = nil
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(4)
                    }
                }

                if let report {
                    results(report)
                } else if running == nil {
                    ContentUnavailableView {
                        Label("No measurements yet", systemImage: "speedometer")
                    } description: {
                        Text("Pick a clip of Tagalog or Taglish speech — a few minutes is "
                             + "plenty — and each tier will be timed on this machine.")
                    }
                }
            }
            .padding(20)
        }
        .fileImporter(isPresented: $picking,
                      allowedContentTypes: AppState.importableTypes) { result in
            if case .success(let url) = result { start(url) }
        }
        .onDisappear { running?.cancel() }
        .task { report = state.settings.loadBenchmark() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model Benchmark").font(.title2.weight(.semibold))
            Text("Published Whisper numbers are English, on other hardware. Neither half "
                 + "transfers. What matters here is narrower: on this Mac, with this "
                 + "audio, which tier still decodes faster than the audio arrives.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                ForEach(ModelTier.allCases) { tier in
                    Toggle(tier.label, isOn: Binding(
                        get: { tiers.contains(tier) },
                        set: { on in if on { tiers.insert(tier) } else { tiers.remove(tier) } }
                    ))
                    .toggleStyle(.button)
                }
                Spacer()
                Button("Choose Audio…") { picking = true }
                    // Blocked, not merely warned about: the benchmark bypasses
                    // the queue, so nothing else would stop it competing with a
                    // live recording for the Neural Engine and mismeasuring both.
                    .disabled(running != nil || tiers.isEmpty || state.isRecording)
            }

            if !clipName.isEmpty {
                Text(clipName).font(.caption).foregroundStyle(.secondary)
            }
            if state.isRecording {
                Label("A recording is in progress. Benchmarking now would compete with it "
                      + "for the Neural Engine and mismeasure both.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func results(_ report: BenchmarkReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(report.machine).font(.caption).foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    Text("Tier").gridColumnAlignment(.leading)
                    Text("Time")
                    Text("RTF")
                    Text("Speed")
                    Text("Peak RAM")
                    Text("")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                Divider().gridCellUnsizedAxes(.horizontal)

                ForEach(report.runs) { run in
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(run.tier?.label ?? run.modelId)
                            Text(run.label).font(.caption2).foregroundStyle(.secondary)
                        }
                        if let failure = run.failure {
                            Text(failure)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .gridCellColumns(5)
                        } else {
                            Text(TimeFormat.short(ms: run.processMs)).monospacedDigit()
                            Text(String(format: "%.3f", run.rtf)).monospacedDigit()
                            Text(String(format: "%.1fx", run.speedup)).monospacedDigit()
                            Text("\(run.peakMemoryMB) MB").monospacedDigit()
                            if run.canKeepUpLive {
                                Label("live", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                    .labelStyle(.titleAndIcon)
                            } else {
                                Label("offline", systemImage: "clock")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Text("RTF is processing time over audio duration; lower is better. Below 1.0 "
                 + "is faster than real time, and roughly below 0.6 is fast enough to keep "
                 + "up with live audio once VAD and the commit policy take their share.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let recommended = report.recommendedTier {
                HStack {
                    Label("Best quality that keeps up: \(recommended.label)",
                          systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Use \(recommended.label)") {
                        state.settings.tier = recommended
                    }
                }
                .padding(.top, 4)
            }

            if let fastest = report.fastestTier,
               fastest != report.recommendedTier {
                HStack {
                    Label("Fastest measured: \(fastest.label)",
                          systemImage: "bolt.fill")
                        .foregroundStyle(.blue)
                    Spacer()
                    Button("Use \(fastest.label)") {
                        state.settings.tier = fastest
                    }
                }
            }
        }
    }

    private func start(_ url: URL) {
        guard running == nil else { return }
        clipName = url.lastPathComponent
        stage = "Preparing audio…"
        fraction = 0

        running = Task {
            defer { running = nil }
            let cacheURL = AudioCache.url(for: UUID(), under: Paths.support)
            do {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }

                _ = try await AudioCache.build(from: url, to: cacheURL) { value in
                    Task { @MainActor in
                        stage = "Preparing audio…"
                        fraction = value
                    }
                }
                let source = try MappedPCM(contentsOf: cacheURL)
                let runner = BenchmarkRunner(engines: state.engines)
                let result = try await runner.run(
                    source: source,
                    tiers: ModelTier.allCases.filter { tiers.contains($0) },
                    language: state.settings.language
                ) { progress in
                    Task { @MainActor in
                        stage = "\(progress.tier.label): \(progress.stage)"
                        fraction = progress.fraction
                    }
                }
                report = result
                state.settings.saveBenchmark(result)
            } catch is CancellationError {
                // Nothing to report; the user asked it to stop.
            } catch {
                state.alert = AppState.AppAlert(title: "Benchmark failed",
                                                message: error.localizedDescription)
            }
            try? FileManager.default.removeItem(at: cacheURL)
        }
    }
}
