import Foundation
import ScriptingBridge

@objc fileprivate protocol SBSpotifyApplication {
    @objc optional var isRunning: Bool { get }
    @objc optional func setSoundVolume(_ value: Int)
    @objc optional func setPlayerPosition(_ value: Double)
}

extension SBApplication: SBSpotifyApplication {}

/// Scripting Bridge wrapper around Spotify for latency-sensitive write paths
/// (volume and seek scrubbers). Reads still go through AppleScriptHelper.
enum SpotifyBridge {
    private static let bundleID = "com.spotify.client"

    private static let shared: SBApplication? = {
        guard let app = SBApplication(bundleIdentifier: bundleID) else { return nil }
        // Fire-and-forget: don't block the UI thread waiting for Spotify to reply,
        // and don't let Spotify foreground itself to ask the user a question.
        app.sendMode = AESendMode(kAENoReply | kAENeverInteract)
        return app
    }()

    @discardableResult
    static func setVolume(_ value: Int) -> Bool {
        let clamped = max(0, min(100, value))
        guard let app = shared, app.isRunning else { return false }
        (app as SBSpotifyApplication).setSoundVolume?(clamped)
        return true
    }

    @discardableResult
    static func setPlaybackPosition(_ seconds: Double) -> Bool {
        guard let app = shared, app.isRunning else { return false }
        (app as SBSpotifyApplication).setPlayerPosition?(max(0, seconds))
        return true
    }
}
