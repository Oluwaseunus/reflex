import Foundation
import Cocoa

/// Helper class for executing AppleScript commands to control media apps
final class AppleScriptHelper {
    /// Result of an AppleScript execution
    struct ExecutionResult {
        let success: Bool
        let output: String?
        let error: Error?
    }

    /// Execute an arbitrary AppleScript
    static func execute(_ script: String) -> ExecutionResult {
        Logger.shared.appleScript("Executing script: \(script.prefix(100))...")

        let appleScript = NSAppleScript(source: script)
        var errorDict: NSDictionary?
        let output = appleScript?.executeAndReturnError(&errorDict)

        if let errorDict = errorDict {
            let errorMessage = errorDict[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            let error = NSError(
                domain: "AppleScriptError",
                code: errorDict[NSAppleScript.errorNumber] as? Int ?? -1,
                userInfo: [NSLocalizedDescriptionKey: errorMessage]
            )
            Logger.shared.appleScriptError(errorMessage, script: script)
            return ExecutionResult(success: false, output: nil, error: error)
        }

        let resultString = output?.stringValue
        Logger.shared.appleScript("Script completed successfully")
        return ExecutionResult(success: true, output: resultString, error: nil)
    }

    /// Check if an app is currently running
    static func isAppRunning(_ app: MediaApp) -> Bool {
        let script = """
        tell application "System Events"
            return (name of processes) contains "\(app.appleScriptName)"
        end tell
        """
        let result = execute(script)
        return result.output?.lowercased() == "true"
    }

    /// Check if an app is currently playing
    static func checkIfAppIsPlaying(_ app: MediaApp) -> Bool {
        let script: String
        switch app.bundleIdentifier {
        case "com.spotify.client":
            script = """
            tell application "Spotify"
                if it is running then
                    return player state is playing
                end if
            end tell
            return false
            """
        case "com.apple.Music":
            script = """
            tell application "Music"
                if it is running then
                    return player state is playing
                end if
            end tell
            return false
            """
        case "org.videolan.vlc":
            script = """
            tell application "VLC"
                if it is running then
                    return playing
                end if
            end tell
            return false
            """
        default:
            script = """
            tell application "\(app.appleScriptName)"
                if it is running then
                    try
                        return player state is playing
                    on error
                        return false
                    end try
                end if
            end tell
            return false
            """
        }

        let result = execute(script)
        return result.output?.lowercased() == "true"
    }

    /// Get current track information from an app
    static func getCurrentTrack(from app: MediaApp) -> (track: String?, artist: String?, album: String?) {
        let script: String
        switch app.bundleIdentifier {
        case "com.spotify.client":
            if SpotifyPlaybackStartupGuard.isSuppressingReads {
                return (nil, nil, nil)
            }
            script = """
            tell application "Spotify"
                if it is running and player state is playing then
                    set trackName to name of current track
                    set artistName to artist of current track
                    set albumName to album of current track
                    return trackName & "|||" & artistName & "|||" & albumName
                end if
            end tell
            return ""
            """
        case "com.apple.Music":
            script = """
            tell application "Music"
                if it is running and player state is playing then
                    set trackName to name of current track
                    set artistName to artist of current track
                    set albumName to album of current track
                    return trackName & "|||" & artistName & "|||" & albumName
                end if
            end tell
            return ""
            """
        default:
            return (nil, nil, nil)
        }

        let result = execute(script)
        guard let output = result.output, !output.isEmpty else {
            return (nil, nil, nil)
        }

        let parts = output.components(separatedBy: "|||")
        return (
            track: parts.count > 0 ? parts[0] : nil,
            artist: parts.count > 1 ? parts[1] : nil,
            album: parts.count > 2 ? parts[2] : nil
        )
    }

    /// Send a media command to an app
    static func sendCommand(_ command: MediaCommand, to app: MediaApp) -> Bool {
        let script = buildCommandScript(command: command, app: app)
        let result = execute(script)
        return result.success
    }

    /// Build the AppleScript for a specific command and app
    private static func buildCommandScript(command: MediaCommand, app: MediaApp) -> String {
        let action: String

        switch app.bundleIdentifier {
        case "com.spotify.client":
            action = spotifyAction(for: command)
        case "com.apple.Music":
            action = musicAction(for: command)
        case "org.videolan.vlc":
            action = vlcAction(for: command)
        default:
            action = genericAction(for: command)
        }

        return """
        tell application "\(app.appleScriptName)"
            \(action)
        end tell
        """
    }

    private static func spotifyAction(for command: MediaCommand) -> String {
        switch command {
        case .playPause: return "playpause"
        case .play: return "play"
        case .pause: return "pause"
        case .nextTrack: return "next track"
        case .previousTrack: return "previous track"
        case .volumeUp: return "set sound volume to (sound volume + 10)"
        case .volumeDown: return "set sound volume to (sound volume - 10)"
        case .stop: return "pause"
        }
    }

    private static func musicAction(for command: MediaCommand) -> String {
        switch command {
        case .playPause: return "playpause"
        case .play: return "play"
        case .pause: return "pause"
        case .nextTrack: return "next track"
        case .previousTrack: return "previous track"
        case .volumeUp: return "set sound volume to (sound volume + 10)"
        case .volumeDown: return "set sound volume to (sound volume - 10)"
        case .stop: return "stop"
        }
    }

    private static func vlcAction(for command: MediaCommand) -> String {
        switch command {
        case .playPause: return "play"
        case .play: return "play"
        case .pause: return "play"  // VLC's "play" toggles; no dedicated pause command
        case .nextTrack: return "next"
        case .previousTrack: return "previous"
        case .volumeUp: return "volumeUp"
        case .volumeDown: return "volumeDown"
        case .stop: return "stop"
        }
    }

    private static func genericAction(for command: MediaCommand) -> String {
        switch command {
        case .playPause: return "playpause"
        case .play: return "play"
        case .pause: return "pause"
        case .nextTrack: return "next track"
        case .previousTrack: return "previous track"
        case .volumeUp: return "set sound volume to (sound volume + 10)"
        case .volumeDown: return "set sound volume to (sound volume - 10)"
        case .stop: return "stop"
        }
    }

    /// Activate (bring to front) an app
    static func activateApp(_ app: MediaApp) {
        let script = """
        tell application "\(app.appleScriptName)"
            activate
        end tell
        """
        _ = execute(script)
    }

    /// Run a script and return the string result
    static func runScript(_ script: String) -> String? {
        let result = execute(script)
        return result.output
    }

    /// Send a harmless Spotify Apple Event so macOS can prompt for Automation access.
    static func requestSpotifyAutomationPermission() -> ExecutionResult {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty else {
            let error = NSError(
                domain: "AppleScriptError",
                code: -600,
                userInfo: [NSLocalizedDescriptionKey: "Open Spotify, then request Automation access again."]
            )
            return ExecutionResult(success: false, output: nil, error: error)
        }

        let script = """
        tell application "Spotify"
            return player state as string
        end tell
        """
        return execute(script)
    }

    // MARK: - Playback Info

    /// Get current playback position in seconds
    static func getPlaybackPosition(from app: MediaApp) -> Double? {
        let script: String
        switch app.bundleIdentifier {
        case "com.spotify.client":
            if SpotifyPlaybackStartupGuard.isSuppressingReads { return nil }
            script = """
            tell application "Spotify"
                if it is running then
                    return player position
                end if
            end tell
            return 0
            """
        case "com.apple.Music":
            script = """
            tell application "Music"
                if it is running then
                    return player position
                end if
            end tell
            return 0
            """
        default:
            return nil
        }

        let result = execute(script)
        guard let output = result.output else { return nil }
        return Double(output)
    }

    /// Get track duration in seconds
    static func getTrackDuration(from app: MediaApp) -> Double? {
        let script: String
        switch app.bundleIdentifier {
        case "com.spotify.client":
            if SpotifyPlaybackStartupGuard.isSuppressingReads { return nil }
            script = """
            tell application "Spotify"
                if it is running then
                    return (duration of current track) / 1000
                end if
            end tell
            return 0
            """
        case "com.apple.Music":
            script = """
            tell application "Music"
                if it is running then
                    return duration of current track
                end if
            end tell
            return 0
            """
        default:
            return nil
        }

        let result = execute(script)
        guard let output = result.output else { return nil }
        return Double(output)
    }

    /// Get album artwork bytes asynchronously.
    static func getArtworkData(from app: MediaApp) async -> Data? {
        switch app.bundleIdentifier {
        case "com.spotify.client":
            if SpotifyPlaybackStartupGuard.isSuppressingReads { return nil }
            let script = """
            tell application "Spotify"
                if it is running then
                    return artwork url of current track
                end if
            end tell
            return ""
            """
            let result = execute(script)
            guard let urlString = result.output, urlString.hasPrefix("http"),
                  let url = URL(string: urlString) else {
                return nil
            }
            return await ArtworkDataCache.shared.data(for: url)

        case "com.apple.Music":
            let script = """
            tell application "Music"
                if it is running then
                    try
                        set artworkData to raw data of artwork 1 of current track
                        return artworkData
                    end try
                end if
            end tell
            return ""
            """
            let appleScript = NSAppleScript(source: script)
            var errorDict: NSDictionary?
            let output = appleScript?.executeAndReturnError(&errorDict)
            if errorDict != nil { return nil }
            return output?.data

        default:
            return nil
        }
    }

    /// Seek the current Spotify track to 0 and start playback, in a single
    /// AppleScript `tell` block so the two statements share one AppleEvent
    /// round-trip and cannot race against a playback-context change. Only
    /// supports Spotify — Music uses a different idiom.
    @discardableResult
    static func restartAndPlaySpotify(for app: MediaApp) -> Bool {
        guard app.bundleIdentifier == "com.spotify.client" else { return false }
        let script = """
        tell application "Spotify"
            if it is running then
                set player position to 0
                play
            end if
        end tell
        """
        return execute(script).success
    }

    /// Skip to the previous Spotify track and start playback, in a single
    /// AppleScript `tell` block. Used for the popover ⏮ button's
    /// paused + position<3s branch, where we want Spotify's native
    /// paused-click-plays-previous-track behavior. Only supports Spotify.
    @discardableResult
    static func previousTrackAndPlaySpotify(for app: MediaApp) -> Bool {
        guard app.bundleIdentifier == "com.spotify.client" else { return false }
        let script = """
        tell application "Spotify"
            if it is running then
                previous track
                play
            end if
        end tell
        """
        return execute(script).success
    }

    /// Set playback position in seconds
    @discardableResult
    static func setPlaybackPosition(_ position: Double, for app: MediaApp) -> Bool {
        let rounded = String(format: "%.1f", position)
        let script: String
        switch app.bundleIdentifier {
        case "com.spotify.client":
            script = """
            tell application "Spotify"
                if it is running then
                    set player position to \(rounded)
                end if
            end tell
            """
        case "com.apple.Music":
            script = """
            tell application "Music"
                if it is running then
                    set player position to \(rounded)
                end if
            end tell
            """
        default:
            return false
        }

        let result = execute(script)
        return result.success
    }

    // MARK: - Volume Control

    /// Get current volume (0-100) for an app
    static func getVolume(for app: MediaApp) -> Int? {
        let script: String
        switch app.bundleIdentifier {
        case "com.spotify.client":
            if SpotifyPlaybackStartupGuard.isSuppressingReads { return nil }
            script = """
            tell application "Spotify"
                if it is running then
                    return sound volume
                end if
            end tell
            return -1
            """
        default:
            return nil
        }

        let result = execute(script)
        guard let output = result.output, let value = Int(output), value >= 0 else { return nil }
        return value
    }

    /// Set volume (0-100) for an app
    @discardableResult
    static func setVolume(_ value: Int, for app: MediaApp) -> Bool {
        let clamped = max(0, min(100, value))
        let script: String
        switch app.bundleIdentifier {
        case "com.spotify.client":
            script = """
            tell application "Spotify"
                if it is running then
                    set sound volume to \(clamped)
                    return sound volume
                end if
            end tell
            return -1
            """
        default:
            return false
        }

        let result = execute(script)
        return result.success
    }

    // MARK: - Spotify Deep Links

    /// Open a Spotify URI/URL (e.g. spotify:album:..., spotify:artist:..., spotify:search:..., https://open.spotify.com/...)
    static func openSpotifyURI(_ uri: String) {
        guard let url = URL(string: uri) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Resolve the currently playing/current selected Spotify track into a canonical spotify:track:<id> URI.
    static func currentSpotifyTrackURI() -> String? {
        let script = """
        tell application "Spotify"
            if it is running then
                try
                    set rawUrl to spotify url of current track
                    return rawUrl
                on error
                    try
                        set rawId to id of current track
                        return rawId
                    on error
                        return ""
                    end try
                end try
            end if
        end tell
        return ""
        """

        let result = execute(script)
        guard let output = result.output, !output.isEmpty else { return nil }
        return normalizeSpotifyTrackURI(output)
    }

    /// Build a Spotify URI that searches for an album (and optional artist).
    /// Spotify AppleScript does not expose album IDs directly, so this uses URI-based search.
    static func spotifyAlbumSearchURI(album: String, artist: String?) -> String {
        let query: String
        if let artist = artist, !artist.isEmpty {
            query = "album:\(album) artist:\(artist)"
        } else {
            query = "album:\(album)"
        }
        return "spotify:search:\(encodeSpotifyQuery(query))"
    }

    /// Build a Spotify URI that searches for an artist.
    /// Spotify AppleScript does not expose artist IDs directly, so this uses URI-based search.
    static func spotifyArtistSearchURI(artist: String) -> String {
        let query = "artist:\(artist)"
        return "spotify:search:\(encodeSpotifyQuery(query))"
    }

    private static func normalizeSpotifyTrackURI(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        if value.hasPrefix("spotify:track:") { return value }

        if value.hasPrefix("https://open.spotify.com/track/") || value.hasPrefix("http://open.spotify.com/track/") {
            let parts = value.components(separatedBy: "/track/")
            guard parts.count > 1 else { return nil }
            let tail = parts[1]
            let id = tail.components(separatedBy: CharacterSet(charactersIn: "?/")).first ?? ""
            return id.isEmpty ? nil : "spotify:track:\(id)"
        }

        // Some AppleScript returns just the ID.
        if !value.contains(":") && !value.contains("/") {
            return "spotify:track:\(value)"
        }

        return nil
    }

    private static func encodeSpotifyQuery(_ query: String) -> String {
        query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
    }
}
