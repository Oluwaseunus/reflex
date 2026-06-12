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

    /// Spotify URI for the current track, when known.
    let spotifyTrackURI: String?

    /// Spotify URI for the current track's album, when known.
    let spotifyAlbumURI: String?

    /// Spotify URI for the current track's primary artist, when known.
    let spotifyArtistURI: String?

    /// When this state was captured
    let timestamp: Date

    init(app: MediaApp?,
         isPlaying: Bool,
         trackName: String?,
         artistName: String?,
         albumName: String?,
         spotifyTrackURI: String? = nil,
         spotifyAlbumURI: String? = nil,
         spotifyArtistURI: String? = nil,
         timestamp: Date) {
        self.app = app
        self.isPlaying = isPlaying
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.spotifyTrackURI = spotifyTrackURI
        self.spotifyAlbumURI = spotifyAlbumURI
        self.spotifyArtistURI = spotifyArtistURI
        self.timestamp = timestamp
    }

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

    /// Next Spotify queue items shown in the popover
    @Published var spotifyQueueItems: [SpotifyQueueItem] = []

    /// Whether a queue refresh is currently in flight
    @Published var isSpotifyQueueLoading: Bool = false

    /// Last queue loading error, suitable for a tooltip
    @Published var spotifyQueueError: String?

    /// Last time the Spotify queue was refreshed
    @Published var spotifyQueueLastUpdate: Date?

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

    /// Update the visible Spotify queue.
    func updateSpotifyQueue(_ items: [SpotifyQueueItem], error: String? = nil) {
        spotifyQueueItems = items
        spotifyQueueError = error
        spotifyQueueLastUpdate = Date()
        isSpotifyQueueLoading = false
    }

    /// Mark the queue as loading.
    func setSpotifyQueueLoading() {
        isSpotifyQueueLoading = true
        spotifyQueueError = nil
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
