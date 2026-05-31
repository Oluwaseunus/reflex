import Foundation
import AppKit

final class SpotifyPlaybackProvider: MediaPlaybackProvider {
    private let bundleID = "com.spotify.client"

    // MARK: - Play (required by protocol)

    func play(item: MediaSearchResult) async throws {
        guard await SpotifyAuthManager.shared.isSignedIn else {
            throw SpotifyUserAPIError.notSignedIn
        }
        try await playViaWebAPI(item: item)
    }

    // MARK: - Queue (only supported when signed in)

    func queue(uri: String) async throws {
        guard await SpotifyAuthManager.shared.isSignedIn else {
            throw SpotifyUserAPIError.notSignedIn
        }
        do {
            try await SpotifyUserAPI.shared.queueTrack(uri: uri)
        } catch SpotifyUserAPIError.noActiveDevice {
            let deviceID = try await ensureActiveDevice()
            try await SpotifyUserAPI.shared.queueTrack(uri: uri, deviceID: deviceID)
        }
    }

    // MARK: - Web API path

    private func playViaWebAPI(item: MediaSearchResult) async throws {
        let request = try await playbackRequest(for: item)
        do {
            try await SpotifyUserAPI.shared.play(
                contextURI: request.contextURI,
                trackURI: request.trackURI
            )
        } catch SpotifyUserAPIError.noActiveDevice {
            let deviceID = try await ensureActiveDevice()
            try await SpotifyUserAPI.shared.play(
                contextURI: request.contextURI,
                trackURI: request.trackURI,
                deviceID: deviceID
            )
        }
        notifyPlaybackStartDispatched(item: item)
    }

    private func playbackRequest(for item: MediaSearchResult) async throws -> (contextURI: String, trackURI: String?) {
        switch item.type {
        case .track:
            let albumContextURI = try await albumContextURI(for: item)
            return (contextURI: albumContextURI, trackURI: item.playbackURI)
        case .album:
            return (contextURI: item.playbackURI, trackURI: nil)
        case .playlist:
            return (contextURI: item.playbackURI, trackURI: nil)
        }
    }

    private func albumContextURI(for item: MediaSearchResult) async throws -> String {
        if let contextURI = item.contextURI, contextURI.hasPrefix("spotify:album:") {
            return contextURI
        }
        return try await SpotifyUserAPI.shared.albumContextURI(forTrackURI: item.playbackURI)
    }

    /// Launch Spotify if it isn't running, then poll GET /me/player/devices
    /// until one appears (up to ~6s). Returns the device ID to target.
    private func ensureActiveDevice() async throws -> String {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if running.isEmpty {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                throw MediaPlaybackError.playerNotRunning
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.addsToRecentItems = false
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        }

        // Spotify takes a couple seconds to register as a Connect device after
        // launch. Poll; prefer the local "Computer" device, fall back to any
        // active device, fall back to the first device we find.
        for _ in 0..<12 {
            let devices = (try? await SpotifyUserAPI.shared.devices()) ?? []
            if let active = devices.first(where: { $0.is_active && $0.id != nil })?.id {
                return active
            }
            if let local = devices.first(where: { $0.type == "Computer" && $0.id != nil })?.id {
                // Not active yet — transfer playback to it so the next play call succeeds.
                try? await SpotifyUserAPI.shared.transferPlayback(to: local)
                return local
            }
            if let any = devices.first(where: { $0.id != nil })?.id {
                try? await SpotifyUserAPI.shared.transferPlayback(to: any)
                return any
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        throw SpotifyUserAPIError.noActiveDevice
    }

    private func notifyPlaybackStartDispatched(item: MediaSearchResult) {
        SpotifyPlaybackStartupGuard.suppressReadsForStartup()
        NotificationCenter.default.post(
            name: Constants.Notifications.spotifyPlaybackStartDispatched,
            object: nil,
            userInfo: [Constants.NotificationUserInfo.spotifyPlaybackItem: item]
        )
    }
}
