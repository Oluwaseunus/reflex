import Foundation
import MediaPlayer

/// Registers Reflex as the system's active "Now Playing" client via MPRemoteCommandCenter.
/// This ensures mediaremoted routes media key commands to Reflex instead of browsers.
/// Commands received here are forwarded to Spotify via the onRemoteCommand callback.
final class NowPlayingManager {
    /// Called when a remote command is received — routes to Spotify via SmartRouter
    var onRemoteCommand: ((MediaCommand) -> Void)?

    private var isRegistered = false

    /// Register Reflex as the active Now Playing client and start handling remote commands.
    func register() {
        guard !isRegistered else { return }

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            Logger.shared.event("MPRemoteCommand: play → routing to Spotify")
            self?.onRemoteCommand?(.play)
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Logger.shared.event("MPRemoteCommand: pause → routing to Spotify")
            self?.onRemoteCommand?(.pause)
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Logger.shared.event("MPRemoteCommand: togglePlayPause → routing to Spotify")
            self?.onRemoteCommand?(.playPause)
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Logger.shared.event("MPRemoteCommand: nextTrack → routing to Spotify")
            self?.onRemoteCommand?(.nextTrack)
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Logger.shared.event("MPRemoteCommand: previousTrack → routing to Spotify")
            self?.onRemoteCommand?(.previousTrack)
            return .success
        }

        // Disable commands we don't handle
        commandCenter.stopCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.changePlaybackRateCommand.isEnabled = false

        // Set initial now-playing info so macOS considers Reflex an active media client
        updateNowPlaying(playing: false)

        isRegistered = true
        Logger.shared.info("NowPlayingManager registered with MPRemoteCommandCenter")
    }

    /// Update the system Now Playing info to reflect the current playback state.
    func updateNowPlaying(
        playing: Bool,
        track: String? = nil,
        artist: String? = nil,
        album: String? = nil
    ) {
        var info: [String: Any] = [:]

        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        info[MPMediaItemPropertyTitle] = track ?? "Reflex"
        if let artist = artist {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let album = album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }

    /// Unregister all remote command handlers.
    func unregister() {
        guard isRegistered else { return }

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

        isRegistered = false
        Logger.shared.info("NowPlayingManager unregistered")
    }

    deinit {
        unregister()
    }
}
