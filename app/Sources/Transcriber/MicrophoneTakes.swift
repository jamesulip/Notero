import Foundation
import TranscriberEngine

/// The microphone test's takes, for the life of the app.
///
/// Kept on `AppState` rather than in the Settings row so that closing and
/// reopening Settings between two microphones does not lose the first take.
/// Newest first, at most `limit`; a take is 32 KB a second.
@Observable
final class MicrophoneTakes {
    static let limit = 6

    private(set) var all: [MicrophoneTake] = []
    /// The take that is sounding now, if any.
    private(set) var playing: UUID?
    private let player = TakePlayer()

    func add(_ take: MicrophoneTake) {
        all.insert(take, at: 0)
        if all.count > Self.limit { all.removeLast(all.count - Self.limit) }
    }

    func remove(_ take: MicrophoneTake) {
        if playing == take.id { stopPlaying() }
        all.removeAll { $0.id == take.id }
    }

    func play(_ take: MicrophoneTake) {
        playing = take.id
        let id = take.id
        player.play(take,
                    onFailure: { message in Task { @MainActor in self.failed(id, message) } },
                    onFinish: { Task { @MainActor in self.finished(id) } })
    }

    /// Why the last playback did not happen, for the row to show.
    private(set) var failure: String?

    func stopPlaying() {
        player.stop()
        playing = nil
    }

    private func finished(_ id: UUID) {
        if playing == id { playing = nil }
    }

    private func failed(_ id: UUID, _ message: String) {
        if playing == id { playing = nil }
        failure = message
    }
}
