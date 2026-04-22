import Foundation
import AppKit

final class SpotifyPlaybackProvider: MediaPlaybackProvider {
    private let bundleID = "com.spotify.client"

    // MARK: - Play (required by protocol)

    func play(item: MediaSearchResult) async throws {
        if await SpotifyAuthManager.shared.isSignedIn {
            try await playViaWebAPI(item: item)
        } else {
            try playViaAppleScript(uri: item.playbackURI)
        }
    }

    /// Bypass the Web API and always go through the local Spotify client via
    /// AppleScript. Used by Shift+Enter so the user can opt into the native
    /// client's implicit-context autoplay. Cost: Spotify self-activates (the
    /// research confirmed no local-client path avoids this); the popup's
    /// closeAfterPlayback re-activates the previous app to mask the flicker.
    func playLocal(item: MediaSearchResult) throws {
        try playViaAppleScript(uri: item.playbackURI)
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
        // For tracks, prefer context=album + offset=track so Spotify continues
        // through the rest of the album (native "click a track in an album"
        // behavior). Falls back to bare-track play if the search didn't
        // surface an album URI. For albums, play the album from the start.
        let contextURI: String?
        let trackURI: String?
        switch item.type {
        case .track:
            contextURI = item.contextURI
            trackURI = item.playbackURI
        case .album:
            contextURI = item.playbackURI
            trackURI = nil
        }
        do {
            try await SpotifyUserAPI.shared.play(contextURI: contextURI, trackURI: trackURI)
        } catch SpotifyUserAPIError.noActiveDevice {
            let deviceID = try await ensureActiveDevice()
            try await SpotifyUserAPI.shared.play(
                contextURI: contextURI,
                trackURI: trackURI,
                deviceID: deviceID
            )
        }
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

    // MARK: - AppleScript fallback (not signed in)

    private func playViaAppleScript(uri: String) throws {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard let app = running.first else {
            throw MediaPlaybackError.playerNotRunning
        }
        let target = NSAppleEventDescriptor(processIdentifier: app.processIdentifier)
        let event = NSAppleEventDescriptor(
            eventClass: fourCharCode("spfy"),
            eventID: fourCharCode("PCtx"),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setParam(NSAppleEventDescriptor(string: uri), forKeyword: keyDirectObject)
        do {
            _ = try event.sendEvent(options: .defaultOptions, timeout: 10)
        } catch {
            throw MediaPlaybackError.internal(underlying: error)
        }
    }

    private func fourCharCode(_ s: String) -> FourCharCode {
        var result: FourCharCode = 0
        for c in s.utf8.prefix(4) {
            result = (result << 8) + FourCharCode(c)
        }
        return result
    }
}
