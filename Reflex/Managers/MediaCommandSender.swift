import Foundation
import Cocoa

/// Sends media commands to target applications via AppleScript
final class MediaCommandSender {
    /// Send a command to a specific app
    /// - Returns: true if command was sent successfully
    @discardableResult
    func sendCommand(_ command: MediaCommand, to app: MediaApp) -> Bool {
        Logger.shared.commandRouted(command: command, to: app)

        let success = AppleScriptHelper.sendCommand(command, to: app)

        if success {
            Logger.shared.info("Command sent successfully: \(command.displayName) -> \(app.name)")
            provideFeedback(for: command)
            notifyCommandSent(command: command, app: app)
        } else {
            Logger.shared.error("Failed to send command: \(command.displayName) -> \(app.name)")
        }

        return success
    }

    /// Provide feedback after sending a command
    private func provideFeedback(for command: MediaCommand) {
        let prefs = PreferencesManager.shared.prefs

        // Visual feedback (handled by StatusBarManager via notification)
        if prefs.showVisualFeedback {
            // Notification triggers UI update
        }

        // Audio feedback
        if prefs.playAudioFeedback {
            NSSound.beep()
        }
    }

    /// Post notification that a command was sent
    private func notifyCommandSent(command: MediaCommand, app: MediaApp) {
        NotificationCenter.default.post(
            name: Constants.Notifications.commandSent,
            object: nil,
            userInfo: [
                "command": command,
                "app": app
            ]
        )
    }

    /// Check if an app can receive commands (is running)
    func canSendCommand(to app: MediaApp) -> Bool {
        app.isRunning
    }

    /// Send play/pause toggle
    func togglePlayPause(to app: MediaApp) -> Bool {
        sendCommand(.playPause, to: app)
    }

    /// Send next track
    func nextTrack(to app: MediaApp) -> Bool {
        sendCommand(.nextTrack, to: app)
    }

    /// Send previous track
    func previousTrack(to app: MediaApp) -> Bool {
        sendCommand(.previousTrack, to: app)
    }

    /// Send volume up
    func volumeUp(to app: MediaApp) -> Bool {
        sendCommand(.volumeUp, to: app)
    }

    /// Send volume down
    func volumeDown(to app: MediaApp) -> Bool {
        sendCommand(.volumeDown, to: app)
    }
}
