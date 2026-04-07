import Foundation
import Combine
import AppKit

/// Represents the current playback state of a media app
struct PlaybackState {
    /// The app currently playing (if any)
    let app: MediaApp?

    /// Whether media is actively playing
    let isPlaying: Bool

    /// Current track name (if available)
    let trackName: String?

    /// Current artist name (if available)
    let artistName: String?

    /// Current album name (if available)
    let albumName: String?

    /// When this state was captured
    let timestamp: Date

    /// Stable identity key for this track (used for dismiss/change detection)
    var trackKey: String {
        "\(trackName ?? "")||\(artistName ?? "")"
    }

    /// Check if state is stale (older than threshold)
    func isStale(threshold: TimeInterval = 30) -> Bool {
        Date().timeIntervalSince(timestamp) > threshold
    }

    static var empty: PlaybackState {
        PlaybackState(app: nil, isPlaying: false, trackName: nil,
                      artistName: nil, albumName: nil, timestamp: Date())
    }
}

/// Observable manager for tracking playback state across the app
class PlaybackStateManager: ObservableObject {
    /// Current playback state (nil if nothing detected)
    @Published var currentState: PlaybackState?

    /// Current album artwork for the active track
    @Published var currentArtwork: NSImage?

    /// The currently active/targeted media app
    @Published var activeApp: MediaApp?

    /// Last time state was updated
    @Published var lastUpdate: Date?

    /// Whether any media app is currently playing
    var isPlaying: Bool {
        currentState?.isPlaying ?? false
    }

    /// Current track info formatted for display
    var nowPlayingText: String? {
        guard let state = currentState, state.isPlaying else { return nil }

        if let track = state.trackName {
            if let artist = state.artistName {
                return "\(track) - \(artist)"
            }
            return track
        }
        return nil
    }

    /// Update state with new playback info
    func updateState(_ state: PlaybackState) {
        currentState = state
        lastUpdate = Date()
        if state.isPlaying {
            activeApp = state.app
        }
    }

    /// Clear current state
    func clearState() {
        currentState = nil
        lastUpdate = Date()
    }

    /// Key identifying the dismissed track (nil if nothing dismissed)
    var dismissedTrackKey: String?

    /// Dismiss the currently displayed track from the menu bar.
    func dismissCurrentTrack() {
        guard let state = currentState else { return }
        dismissedTrackKey = state.trackKey
        currentState = nil
        currentArtwork = nil
        lastUpdate = Date()
    }
}
