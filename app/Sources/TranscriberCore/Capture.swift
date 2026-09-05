import Foundation

/// Where the audio of a lane came from, which is also who is speaking on it.
///
/// The distinction is free speaker separation and the reason two lanes are
/// worth keeping apart at all: nobody in the room is ever on the remote lane,
/// and nobody on the call is ever on the room lane. No clustering, no
/// embeddings, no threshold to tune -- the boundary is a fact about where the
/// samples came from.
public enum CaptureLane: String, Sendable, CaseIterable, Codable {
    /// The microphone: whoever is in the room.
    case room
    /// This Mac's own output: whoever is on the call.
    case remote

    /// What a transcript calls this lane when both are present.
    public var speakerLabel: String {
        switch self {
        case .room: return "Room"
        case .remote: return "Remote"
        }
    }
}

/// What a recording listens to.
///
/// A hybrid meeting needs both, and neither is a superset of the other. The
/// microphone cannot hear the people on the call except as speaker output
/// bounced off a wall, and the system tap cannot hear the room at all. Picking
/// one is picking half the meeting; the default stays `microphone` because
/// that is what an in-person meeting is, and because it is the only choice
/// that needs no second permission.
public enum CaptureSource: String, Sendable, CaseIterable, Codable {
    case microphone
    case systemAudio
    case both

    public static let `default` = CaptureSource.microphone

    public var lanes: [CaptureLane] {
        switch self {
        case .microphone: return [.room]
        case .systemAudio: return [.remote]
        case .both: return [.room, .remote]
        }
    }

    public var usesMicrophone: Bool { self != .systemAudio }
    public var usesSystemAudio: Bool { self != .microphone }

    public var label: String {
        switch self {
        case .microphone: return "Microphone"
        case .systemAudio: return "This Mac's audio"
        case .both: return "Microphone and this Mac's audio"
        }
    }

    public var detail: String {
        switch self {
        case .microphone:
            return "People in the room. What an in-person meeting needs."
        case .systemAudio:
            return "People on the call, captured before the speakers. Nothing in "
                 + "the room is recorded."
        case .both:
            return "Both, kept as separate tracks so the transcript can tell the "
                 + "room from the call."
        }
    }
}

/// Which channel of the archive holds which lane.
///
/// A two-lane recording is one stereo file rather than two mono ones: the
/// channels come off a single clock, so they cannot drift apart, and a player
/// that knows nothing about lanes still plays the meeting.
public enum ArchiveChannels {
    public static func channel(for lane: CaptureLane) -> Int {
        switch lane {
        case .room: return 0
        case .remote: return 1
        }
    }

    public static func lane(atChannel channel: Int, of lanes: [CaptureLane]) -> CaptureLane? {
        lanes.count == 1 ? lanes.first : lanes.first { self.channel(for: $0) == channel }
    }
}
