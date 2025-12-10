import Foundation

/// Represents media control commands that can be sent to apps
enum MediaCommand: String, CaseIterable {
    case playPause
    case nextTrack
    case previousTrack
    case volumeUp
    case volumeDown
    case stop

    /// NX_KEYTYPE values for system media keys
    var keyCode: Int {
        switch self {
        case .playPause: return 16
        case .nextTrack: return 17
        case .previousTrack: return 18
        case .volumeUp: return 0
        case .volumeDown: return 1
        case .stop: return 16  // Same as playPause, context-dependent
        }
    }

    /// AppleScript command string for this action
    var appleScriptCommand: String {
        switch self {
        case .playPause: return "playpause"
        case .nextTrack: return "next track"
        case .previousTrack: return "previous track"
        case .volumeUp: return "set sound volume to (sound volume + 10)"
        case .volumeDown: return "set sound volume to (sound volume - 10)"
        case .stop: return "stop"
        }
    }

    /// Human-readable description
    var displayName: String {
        switch self {
        case .playPause: return "Play/Pause"
        case .nextTrack: return "Next Track"
        case .previousTrack: return "Previous Track"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .stop: return "Stop"
        }
    }

    /// SF Symbol for this command
    var symbolName: String {
        switch self {
        case .playPause: return "playpause.fill"
        case .nextTrack: return "forward.fill"
        case .previousTrack: return "backward.fill"
        case .volumeUp: return "speaker.wave.3.fill"
        case .volumeDown: return "speaker.wave.1.fill"
        case .stop: return "stop.fill"
        }
    }
}
