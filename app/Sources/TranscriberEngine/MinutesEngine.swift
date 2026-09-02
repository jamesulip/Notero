import Foundation
import os
import TranscriberCore

/// Generating minutes from a finished transcript.
///
/// A fourth seam alongside `SpeechRecognizing`, `VoiceActivityDetecting` and
/// `SpeakerDiarizing`, for the same reason: the thing behind it is replaceable.
/// Today it is the Claude CLI; a local MLX model conforming to this would be
/// a new conformance and nothing else.
public protocol MinutesGenerating: Sendable {
    /// Raw model output for `prompt`. Parsing and validation are the caller's,
    /// in `Minutes.parse`.
    func generate(prompt: String) async throws -> String
}

/// Minutes via the Claude Code CLI, using whatever subscription that CLI is
/// already signed in to.
///
/// **This sends the transcript off the machine.** Everything else in this app
/// runs locally by design; this does not, and the UI says so before it runs.
/// Audio still never leaves -- only text.
public struct ClaudeCLIMinutes: MinutesGenerating {

    public enum Failure: LocalizedError {
        case cliNotFound([String])
        case timedOut(seconds: Int)
        case failed(status: Int32, stderr: String)

        public var errorDescription: String? {
            switch self {
            case .cliNotFound(let searched):
                return "The `claude` command was not found. Looked in:\n"
                    + searched.joined(separator: "\n")
                    + "\n\nInstall Claude Code and sign in, then try again."
            case .timedOut(let seconds):
                return "Claude did not answer within \(seconds) seconds."
            case .failed(let status, let stderr):
                let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return "Claude exited with code \(status)."
                    + (detail.isEmpty ? "" : "\n\n\(detail)")
            }
        }
    }

    /// Where to look for the binary, in order.
    ///
    /// A `.app` launched from Finder inherits launchd's PATH, not the shell's
    /// -- `/usr/bin:/bin:/usr/sbin:/sbin` and nothing else. Every place a
    /// person actually installs Claude Code is outside that, so resolving it
    /// through `env` finds nothing when it matters and works when testing from
    /// a terminal. Hence an explicit list.
    public static func candidatePaths() -> [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "/usr/bin/claude",
        ]
    }

    let executable: String?
    let timeoutSeconds: Int

    /// - Parameter executable: an explicit path, or nil to search.
    public init(executable: String? = nil, timeoutSeconds: Int = 300) {
        self.executable = executable?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        self.timeoutSeconds = timeoutSeconds
    }

    static func resolve(_ override: String?) throws -> String {
        if let override {
            guard FileManager.default.isExecutableFile(atPath: override) else {
                throw Failure.cliNotFound([override])
            }
            return override
        }
        let candidates = candidatePaths()
        guard let found = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else { throw Failure.cliNotFound(candidates) }
        return found
    }

    public func generate(prompt: String) async throws -> String {
        let binary = try Self.resolve(executable)
        let seconds = timeoutSeconds

        return try await withCheckedThrowingContinuation { continuation in
            // The continuation must resume exactly once, and both the timeout
            // and the exit handler race to do it.
            let resumed = OSAllocatedUnfairLock(initialState: false)
            @Sendable func finish(_ result: Result<String, Error>) {
                let first = resumed.withLock { done -> Bool in
                    if done { return false }
                    done = true
                    return true
                }
                if first { continuation.resume(with: result) }
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["-p", "--output-format", "text"]
            // An empty directory: `claude` picks up CLAUDE.md and project files
            // from its working directory, and none of that belongs in a
            // summary of someone's meeting.
            process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())

            let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            // Read both pipes concurrently. Draining only at exit deadlocks as
            // soon as either fills its 64 KB buffer, and a long meeting's
            // minutes clear that.
            let out = PipeDrain(stdout), err = PipeDrain(stderr)

            process.terminationHandler = { proc in
                let text = out.text(), errorText = err.text()
                if proc.terminationStatus == 0 {
                    finish(.success(text))
                } else {
                    finish(.failure(Failure.failed(status: proc.terminationStatus,
                                                   stderr: errorText)))
                }
            }

            do {
                try process.run()
            } catch {
                finish(.failure(error))
                return
            }

            stdin.fileHandleForWriting.write(Data(prompt.utf8))
            try? stdin.fileHandleForWriting.close()

            Task {
                try? await Task.sleep(for: .seconds(seconds))
                guard process.isRunning else { return }
                process.terminate()
                finish(.failure(Failure.timedOut(seconds: seconds)))
            }
        }
    }
}

/// Accumulates a pipe's output on its own queue.
private final class PipeDrain: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    init(_ pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { [self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            lock.withLock { data.append(chunk) }
        }
    }

    func text() -> String {
        lock.withLock { String(decoding: data, as: UTF8.self) }
    }
}

private extension String {
    var nilIfBlank: String? { isEmpty ? nil : self }
}
