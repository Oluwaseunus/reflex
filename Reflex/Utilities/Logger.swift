import Foundation
import os.log

/// Centralized logging utility using unified logging
final class Logger {
    static let shared = Logger()

    private let subsystem = Constants.App.bundleIdentifier

    private lazy var mainLogger = os.Logger(subsystem: subsystem, category: "main")
    private lazy var eventsLogger = os.Logger(subsystem: subsystem, category: "events")
    private lazy var appleScriptLogger = os.Logger(subsystem: subsystem, category: "applescript")
    private lazy var routingLogger = os.Logger(subsystem: subsystem, category: "routing")

    private init() {}

    // MARK: - Main Category

    func info(_ message: String) {
        mainLogger.info("\(message, privacy: .public)")
    }

    func debug(_ message: String) {
        mainLogger.debug("\(message, privacy: .public)")
    }

    func error(_ message: String, error: Error? = nil) {
        if let error = error {
            mainLogger.error("\(message, privacy: .public): \(error.localizedDescription, privacy: .public)")
        } else {
            mainLogger.error("\(message, privacy: .public)")
        }
    }

    func warning(_ message: String) {
        mainLogger.warning("\(message, privacy: .public)")
    }

    // MARK: - Events Category

    func event(_ message: String) {
        eventsLogger.info("[EVENT] \(message, privacy: .public)")
    }

    // MARK: - AppleScript Category

    func appleScript(_ message: String) {
        appleScriptLogger.debug("[AS] \(message, privacy: .public)")
    }

    func appleScriptError(_ message: String, script: String? = nil) {
        if let script = script {
            appleScriptLogger.error("[AS ERROR] \(message, privacy: .public) - Script: \(script, privacy: .public)")
        } else {
            appleScriptLogger.error("[AS ERROR] \(message, privacy: .public)")
        }
    }

    // MARK: - Routing Category

    func routing(_ message: String) {
        routingLogger.debug("[ROUTE] \(message, privacy: .public)")
    }

    func commandRouted(command: MediaCommand, to app: MediaApp) {
        routingLogger.info("[ROUTE] \(command.displayName, privacy: .public) -> \(app.name, privacy: .public)")
    }
}
