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
}
