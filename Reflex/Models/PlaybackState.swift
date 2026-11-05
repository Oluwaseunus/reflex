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

    /// Current artist display name (if available)
    let artistName: String?

    /// Current album name (if available)
    let albumName: String?

    /// Identity supplied by the player (Spotify URI or Music persistent ID).
    let trackIdentifier: String?
    let position: Double?
    let duration: Double?
    let volume: Int?

    var spotifyTrackURI: String? {
        app?.bundleIdentifier == PlaybackPlayer.spotify.rawValue ? trackIdentifier : nil
    }

    /// When this state was captured
    let timestamp: Date

    init(app: MediaApp?,
         isPlaying: Bool,
         trackName: String?,
         artistName: String?,
         albumName: String?,
         spotifyTrackURI: String? = nil,
         trackIdentifier: String? = nil,
         position: Double? = nil,
         duration: Double? = nil,
         volume: Int? = nil,
         timestamp: Date) {
        self.app = app
        self.isPlaying = isPlaying
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.trackIdentifier = trackIdentifier ?? spotifyTrackURI
        self.position = position
        self.duration = duration
        self.volume = volume
        self.timestamp = timestamp
    }

    /// Stable identity key for this track (used for dismiss/change detection)
    var trackKey: String {
        let identity = trackIdentifier.flatMap { $0.isEmpty ? nil : $0 }
            ?? "\(trackName ?? "")||\(artistName ?? "")||\(albumName ?? "")"
        return "\(app?.bundleIdentifier ?? "")||\(identity)"
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

    /// MusicKit identities and relationships for the displayed Apple Music track.
    @Published var currentCatalogDetails: AppleMusicCatalogDetails?

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
        if currentState?.trackKey != state.trackKey { currentCatalogDetails = nil }
        currentState = state
        lastUpdate = Date()
        activeApp = state.app
    }

    /// Clear current state
    func clearState() {
        currentState = nil
        currentCatalogDetails = nil
        currentArtwork = nil
        activeApp = nil
        dismissedTrackKey = nil
        lastUpdate = Date()
    }

    /// Key identifying the dismissed track (nil if nothing dismissed)
    var dismissedTrackKey: String?

    /// Dismiss the currently displayed track from the menu bar.
    func dismissCurrentTrack() {
        guard let state = currentState else { return }
        dismissedTrackKey = state.trackKey
        currentState = nil
        currentCatalogDetails = nil
        currentArtwork = nil
        lastUpdate = Date()
    }
}
