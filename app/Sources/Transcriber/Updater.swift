import AppKit
import Foundation
import Observation
import TranscriberCore

/// Finds, checks and installs a new version of the app.
///
/// The decisions live in `TranscriberCore/Update.swift`, where they are tested
/// without a network. This file is the parts that need a Mac: the request, the
/// download, the unpack, and the swap that a running app cannot do to itself.
///
/// **The swap.** A process cannot replace the bundle it is executing out of and
/// survive doing it: pages of the old executable are still mapped, and faulting
/// one in after the file has gone crashes the app. So the app writes a short
/// shell script, starts it, and quits. The script waits for the process to go,
/// moves the new bundle into place, and reopens it. The window in which no app
/// exists at the destination is one `mv` on one volume, and the old bundle is
/// kept until the new one is in place so that a failure can put it back.
///
/// **What it will not do.** It will not install a download it cannot check
/// against `UpdateSource.publicKey` (see `UpdateVerifier`), it will not ask for
/// an administrator password, and it will not touch a bundle in a folder the
/// user cannot write. Each of those refusals says so and offers the releases
/// page instead.
@Observable
final class Updater {

    /// Where the update is up to. One case per thing the sheet has to say.
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        /// Fraction downloaded, 0...1.
        case downloading(Release, Double)
        case verifying(Release)
        /// Checked, unpacked, and waiting at this path for the user to say go.
        case ready(Release, URL)
        case quitting
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// The sheet is up. Set by the menu item, and by an automatic check that
    /// found something.
    var isPresented = false

    private let settings: AppSettings
    /// Nil when the app is not running from a bundle -- `swift run`, or the
    /// binary invoked straight out of `.build`. Checking still works; the
    /// install refuses, because there is nothing to replace.
    private let installedBundle: URL?
    private let currentVersion: AppVersion?
    private var work: Task<Void, Never>?

    /// One check a day is enough for an app that ships every few weeks, and it
    /// keeps the unauthenticated rate limit far out of reach.
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    init(settings: AppSettings, bundle: Bundle = .main) {
        self.settings = settings
        let url = bundle.bundleURL
        installedBundle = url.pathExtension == "app" ? url : nil
        currentVersion = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String)
            .flatMap(AppVersion.init)
    }

    // MARK: - What the sheet reads

    var versionText: String { currentVersion.map(String.init(describing:)) ?? "unknown" }

    var lastChecked: Date? { settings.lastUpdateCheck }

    /// False in a build with no update key, and in one that is not installed.
    /// The sheet says which, rather than showing a button that cannot work.
    var canInstall: Bool { UpdateSource.canInstall && installedBundle != nil }

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .verifying, .quitting: return true
        case .idle, .upToDate, .available, .ready, .failed: return false
        }
    }

    // MARK: - Checking

    /// Asks GitHub again, now.
    ///
    /// `present` is false from the Settings pane, which reports the answer in
    /// its own window: the sheet belongs to the main window, so raising it
    /// from Settings would put the answer behind the window the user is
    /// looking at. The pane offers a button that brings it forward instead.
    func checkNow(present: Bool = true) {
        if present { isPresented = true }
        check(announceOnlyIfFound: false)
    }

    /// From the Settings pane, once a check has found something: put the sheet
    /// up on the main window, where the download and install buttons live.
    func showDetails() {
        isPresented = true
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// A one-line answer for the Settings pane. Nil while there is nothing
    /// to say, so the pane does not show an empty row before the first check.
    var statusLine: String? {
        switch phase {
        case .idle: return nil
        case .checking: return "Checking…"
        case .upToDate: return "This is the newest version."
        case .available(let release): return "Version \(release.version) is available."
        case .downloading(_, let fraction): return "Downloading… \(Int(fraction * 100))%"
        case .verifying: return "Checking the signature…"
        case .ready(let release, _): return "Version \(release.version) is ready to install."
        case .quitting: return "Quitting to install…"
        case .failed(let reason): return reason
        }
    }

    /// True when the sheet has something the pane cannot do for itself.
    var hasDetails: Bool {
        switch phase {
        case .available, .ready: return true
        default: return false
        }
    }

    var didFail: Bool {
        if case .failed = phase { return true }
        return false
    }

    /// Launch. Does nothing unless the user turned automatic checks on and a
    /// day has passed, and opens the sheet only if there is something to say.
    func checkOnLaunch() {
        guard settings.automaticUpdateChecks else { return }
        if let last = settings.lastUpdateCheck,
           Date().timeIntervalSince(last) < Self.checkInterval { return }
        check(announceOnlyIfFound: true)
    }

    private func check(announceOnlyIfFound: Bool) {
        guard let currentVersion else {
            phase = .failed(UpdateError.notAnInstalledApp.localizedDescription)
            return
        }
        work?.cancel()
        phase = .checking
        work = Task { [weak self] in
            do {
                let releases = try await Self.fetchReleases()
                guard !Task.isCancelled, let self else { return }
                settings.lastUpdateCheck = Date()
                let skipped = settings.skippedUpdate.flatMap(AppVersion.init)
                if let release = UpdateCheck.newest(in: releases,
                                                    after: currentVersion,
                                                    skipping: skipped) {
                    phase = .available(release)
                    if announceOnlyIfFound { isPresented = true }
                } else {
                    phase = .upToDate
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                // The attempt is recorded even though it failed. Otherwise a
                // Mac that is offline asks again at every launch, forever.
                settings.lastUpdateCheck = Date()
                phase = .failed(error.localizedDescription)
                if announceOnlyIfFound { isPresented = false }
            }
        }
    }

    /// Not offered again until a newer one appears.
    func skip(_ release: Release) {
        settings.skippedUpdate = String(describing: release.version)
        phase = .upToDate
        isPresented = false
    }

    func cancel() {
        work?.cancel()
        work = nil
        phase = .idle
    }

    // MARK: - Downloading

    /// Fetches the zip and its signature, checks the signature, unpacks the
    /// bundle and checks that it is the app it claims to be. Stops there:
    /// nothing is replaced until `install` is called.
    func download(_ release: Release) {
        guard UpdateSource.canInstall else {
            phase = .failed(UpdateError.noPublicKey.localizedDescription)
            return
        }
        guard let zip = release.appZip, let signature = release.signature else {
            phase = .failed(UpdateError.unexpectedBundle("The release has no signed zip.").localizedDescription)
            return
        }
        work?.cancel()
        phase = .downloading(release, 0)
        work = Task { [weak self] in
            do {
                let staging = try Self.newStagingDirectory()
                let zipURL = try await Self.download(zip, into: staging) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, case .downloading = self.phase else { return }
                        self.phase = .downloading(release, fraction)
                    }
                }
                let signatureURL = try await Self.download(signature, into: staging, progress: nil)
                guard !Task.isCancelled, let self else { return }
                phase = .verifying(release)

                let bundleID = Bundle.main.bundleIdentifier ?? "local.transcriber"
                let unpacked = try await Task.detached(priority: .userInitiated) {
                    try Self.verifyAndUnpack(zip: zipURL,
                                             signature: signatureURL,
                                             release: release,
                                             bundleID: bundleID,
                                             into: staging)
                }.value

                guard !Task.isCancelled else { return }
                phase = .ready(release, unpacked)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Installing

    /// Hands the swap to a shell script and quits. Returns without quitting if
    /// the swap cannot be set up, so a refusal is visible rather than silent.
    func install(_ release: Release, from unpacked: URL) {
        guard let destination = installedBundle else {
            phase = .failed(UpdateError.notAnInstalledApp.localizedDescription)
            return
        }
        let parent = destination.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            phase = .failed(UpdateError.locationNotWritable(parent.path).localizedDescription)
            return
        }
        do {
            try Self.startSwap(from: unpacked, to: destination)
            phase = .quitting
            settings.skippedUpdate = nil
            // The sheet has to come down first. macOS refuses to quit an app
            // that has a sheet up, so terminating with this one still on screen
            // does nothing at all: the swap script waits its 30 s, gives up,
            // and leaves the old version in place. Measured, not guessed.
            isPresented = false
            Task {
                // Long enough for SwiftUI to take the sheet off the window.
                // Then quit the normal way, so SwiftData gets its save.
                try? await Task.sleep(for: .milliseconds(300))
                NSApplication.shared.terminate(nil)
            }
        } catch {
            phase = .failed("The update could not be started. \(error.localizedDescription)")
        }
    }

    /// For the "install it yourself" path: shows the checked bundle in Finder.
    func revealInFinder(_ unpacked: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([unpacked])
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(UpdateSource.releasesPageURL)
    }

    // MARK: - The network

    private nonisolated static func fetchReleases() async throws -> [Release] {
        var request = URLRequest(url: UpdateSource.releasesURL)
        // The documented media type, so a future default on the endpoint
        // cannot change the shape of the reply underneath the decoder.
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Transcriber", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        // Nothing about this Mac is worth sending, and nothing is worth keeping.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure(Self.explain(http.statusCode))
        }
        return try ReleaseFeed.releases(from: data)
    }

    /// 404 is the answer a private repository gives, and "not found" on its own
    /// sends the reader looking for a typo instead of at the cause.
    private nonisolated static func explain(_ status: Int) -> String {
        switch status {
        case 404:
            return "The list of releases is not readable. Either nothing has been "
                 + "released yet, or the repository is private -- this app sends no "
                 + "token and cannot read a private one. See docs/RELEASE.md."
        case 403, 429:
            return "GitHub is rate-limiting this Mac (\(status)). Try again later."
        default:
            return "GitHub answered \(status) when asked for the list of releases."
        }
    }

    /// Downloads to a file in `directory`, reporting whole percents.
    ///
    /// A download task with a delegate, not `URLSession.bytes`. `bytes` is the
    /// obvious way to get a progress bar and is unusable for a file this size:
    /// it hands over one `UInt8` at a time through the async-sequence
    /// machinery, and took 62 s for the 10 MB bundle served from localhost.
    /// The same file over a download task is under a second.
    private nonisolated static func download(_ asset: ReleaseAsset,
                                             into directory: URL,
                                             progress: (@Sendable (Double) -> Void)?) async throws -> URL {
        var request = URLRequest(url: asset.url)
        request.setValue("Transcriber", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60
        let destination = directory.appendingPathComponent(asset.name)
        return try await Download(destination: destination, onProgress: progress).run(request)
    }

    /// One download, from `resume` to the file landing at `destination`.
    ///
    /// `URLSession` keeps its delegate alive until the session is invalidated,
    /// and delivers every callback on one serial queue. The lock is for the
    /// continuation only, which `cancel` can also reach.
    private final class Download: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

        private let destination: URL
        private let onProgress: (@Sendable (Double) -> Void)?
        private let lock = NSLock()
        private var continuation: CheckedContinuation<URL, any Error>?
        private var session: URLSession?
        private var lastPercent = -1

        init(destination: URL, onProgress: (@Sendable (Double) -> Void)?) {
            self.destination = destination
            self.onProgress = onProgress
        }

        func run(_ request: URLRequest) async throws -> URL {
            let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
            self.session = session
            let task = session.downloadTask(with: request)
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    lock.lock()
                    self.continuation = continuation
                    lock.unlock()
                    task.resume()
                }
            } onCancel: {
                // The Cancel button. Without this the transfer runs to the end
                // in the background and the task above never returns.
                task.cancel()
            }
        }

        private func finish(_ result: Result<URL, any Error>) {
            lock.lock()
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(with: result)
            session?.finishTasksAndInvalidate()
        }

        func urlSession(_ session: URLSession,
                        downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let percent = Int(fraction * 100)
            guard percent != lastPercent else { return }
            lastPercent = percent
            onProgress?(min(1, fraction))
        }

        func urlSession(_ session: URLSession,
                        downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            if let http = downloadTask.response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                finish(.failure(Failure("The download of \(destination.lastPathComponent) "
                                        + "answered \(http.statusCode).")))
                return
            }
            // The move has to happen here. URLSession deletes the temporary
            // file the moment this method returns.
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
                onProgress?(1)
                finish(.success(destination))
            } catch {
                finish(.failure(error))
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            // Success already went out from didFinishDownloadingTo, and finish
            // ignores a second call.
            if let error { finish(.failure(error)) }
        }
    }

    // MARK: - The file work

    /// Under the app's own Application Support directory rather than `/tmp`:
    /// a staged bundle is up to a few hundred megabytes, and it must not be
    /// swept away between the check and the click that installs it.
    private nonisolated static func newStagingDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Transcriber/Updates", isDirectory: true)
        // One directory per attempt; the previous ones are dead weight.
        try? FileManager.default.removeItem(at: base)
        let directory = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Checks the signature, unpacks, and refuses anything that is not the app
    /// at the version the release promised. Returns the unpacked bundle.
    private nonisolated static func verifyAndUnpack(zip: URL,
                                                    signature signatureURL: URL,
                                                    release: Release,
                                                    bundleID: String,
                                                    into staging: URL) throws -> URL {
        let text = try String(contentsOf: signatureURL, encoding: .utf8)
        let signature = try ReleaseSignature.parse(text)
        try UpdateVerifier.verify(fileAt: zip, against: signature)

        let unpackDir = staging.appendingPathComponent("unpacked", isDirectory: true)
        try FileManager.default.createDirectory(at: unpackDir, withIntermediateDirectories: true)
        // ditto, not unzip: the executable bit and the signature's resource
        // rules have to survive the round trip, and unzip drops both.
        let result = try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpackDir.path])
        guard result.status == 0 else {
            throw Failure("The download could not be unpacked. \(result.output)")
        }

        let contents = try FileManager.default.contentsOfDirectory(at: unpackDir,
                                                                   includingPropertiesForKeys: nil)
        let apps = contents.filter { $0.pathExtension == "app" }
        guard apps.count == 1, let app = apps.first else {
            throw UpdateError.unexpectedBundle("It holds \(apps.count) app bundles, not one.")
        }

        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any] else {
            throw UpdateError.unexpectedBundle("It has no readable Info.plist.")
        }
        guard info["CFBundleIdentifier"] as? String == bundleID else {
            throw UpdateError.unexpectedBundle("It is a different application.")
        }
        guard let shortVersion = info["CFBundleShortVersionString"] as? String,
              let version = AppVersion(shortVersion), version == release.version else {
            throw UpdateError.unexpectedBundle(
                "It says it is version \(info["CFBundleShortVersionString"] as? String ?? "unknown"), "
                + "and the release says \(release.version).")
        }

        // The signature is ad-hoc, so this proves the bundle is internally
        // whole, not who made it. Who made it is the Ed25519 check above.
        let verified = try run("/usr/bin/codesign", ["--verify", "--strict", app.path])
        guard verified.status == 0 else {
            throw UpdateError.unexpectedBundle("Its own code signature is broken. \(verified.output)")
        }
        return app
    }

    /// Writes the swap script, starts it, and returns. The caller quits next.
    private nonisolated static func startSwap(from unpacked: URL, to destination: URL) throws {
        let script = unpacked.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("swap.sh")
        try Self.swapScript.write(to: script, atomically: true, encoding: .utf8)

        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Transcriber", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            script.path,
            String(ProcessInfo.processInfo.processIdentifier),
            unpacked.path,
            destination.path,
            logs.appendingPathComponent("update.log").path,
        ]
        try process.run()
    }

    /// Waits for the app to quit, then swaps the bundle and reopens it.
    ///
    /// The old bundle is moved aside rather than deleted, and put back if the
    /// move of the new one fails. Everything it says goes to a log, because
    /// the app that would otherwise report a failure is gone by then.
    private nonisolated static let swapScript = """
    #!/bin/sh
    # Written by Transcriber's updater. Safe to delete.
    pid=$1
    new=$2
    dest=$3
    log=$4

    exec >>"$log" 2>&1
    echo "--- $(date): replacing $dest with $new"

    # Up to 30 s for the app to go. If it will not, leave everything alone.
    waited=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$waited" -ge 300 ]; then
            echo "the app did not quit; nothing was changed"
            exit 1
        fi
        sleep 0.1
        waited=$((waited + 1))
    done

    # Copy onto the destination volume first, so the step that leaves the
    # destination empty is a rename on one volume rather than a long copy.
    staged="$dest.new-$$"
    rm -rf "$staged"
    if ! ditto "$new" "$staged"; then
        echo "could not stage the new bundle"
        rm -rf "$staged"
        exit 1
    fi

    backup="$dest.old-$$"
    if ! mv "$dest" "$backup"; then
        echo "could not move the old bundle aside"
        rm -rf "$staged"
        exit 1
    fi
    if ! mv "$staged" "$dest"; then
        echo "could not move the new bundle into place; putting the old one back"
        mv "$backup" "$dest"
        exit 1
    fi

    rm -rf "$backup"
    rm -rf "$(dirname "$(dirname "$new")")"
    echo "replaced; reopening"
    open "$dest"
    """

    // MARK: - Shelling out

    private nonisolated static func run(_ tool: String, _ arguments: [String]) throws
        -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A message that is already fit to show. The typed cases live in
    /// `UpdateError`; this is for the one-off strings around them.
    private struct Failure: Error, LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
