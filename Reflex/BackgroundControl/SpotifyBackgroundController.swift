import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class SpotifyBackgroundController {
    static let shared = SpotifyBackgroundController()

    private let spotifyBundleID = "com.spotify.client"
    private let logger = Logger.shared
    private var isRunning = false
    private let accessibilityPollInterval = Duration.milliseconds(250)
    private let searchNavigationTimeout = Duration.seconds(10)
    private let playbackTimeout = Duration.seconds(8)
    private let rootTraversalLimit = 6_000
    private let tableTraversalLimit = 2_000
    private let rowTraversalLimit = 100

    private init() {}

    func play(query: String, preserving expectedForeground: NSRunningApplication?) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isRunning else { return }
        guard AXIsProcessTrusted() else {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
            logger.error("Spotify background control requires Accessibility permission")
            return
        }

        isRunning = true
        Task {
            defer { isRunning = false }
            do {
                let application = try await spotifyAccessibilityApplication()
                try verifyForeground(expectedForeground)
                try await submitSpotifySearch(query: query, in: application, preserving: expectedForeground)
                try verifyForeground(expectedForeground)

                guard let result = await waitForAccessibilityElement(
                    named: "matching Spotify search result",
                    timeout: searchNavigationTimeout,
                    find: { matchingSearchResult(for: query, in: application) }
                ) else {
                    logAccessibilitySummary(in: application)
                    throw BackgroundControlError.matchingTrackNotFound
                }
                try verifyForeground(expectedForeground)
                // Play from the row that exposed the matched track URI. Spotify's
                // `play track` scripting command opens the track's album context and
                // can bring Spotify forward; the search-row action stays in search.
                let pressResult = AXUIElementPerformAction(
                    result.playButton,
                    kAXPressAction as CFString
                )
                guard pressResult == .success else {
                    throw BackgroundControlError.accessibilityActionFailed(
                        "Spotify's matching Play button could not be pressed (\(pressResult.rawValue))."
                    )
                }
                logger.info("Pressed Spotify search-result Play button")
                try verifyForeground(expectedForeground)
                guard await waitForAccessibilityCondition(
                    named: "selected track playing",
                    timeout: playbackTimeout,
                    condition: { AppleScriptHelper.isSpotifyPlayingTrack(result.identity.trackURI) }
                ) else {
                    throw BackgroundControlError.playbackNotVerified(query)
                }
                try verifyForeground(expectedForeground)
                logger.info("Spotify background playback verified; foreground preserved")
            } catch {
                logger.error("Spotify background control failed", error: error)
            }
        }
    }

    private func submitSpotifySearch(
        query: String,
        in application: AXUIElement,
        preserving foreground: NSRunningApplication?
    ) async throws {
        // Spotify's URL handler activates its window even when Launch Services
        // receives activates=false. Never use a search URL here, including as a fallback.
        guard let field = await waitForAccessibilityElement(
            named: "Spotify search field", timeout: searchNavigationTimeout,
            find: { spotifySearchField(in: application) }
        ) else {
            throw BackgroundControlError.accessibilityActionFailed("Spotify's search field is unavailable.")
        }
        let valueResult = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, query as CFString)
        guard valueResult == .success else {
            throw BackgroundControlError.accessibilityActionFailed("Search text could not be set (\(valueResult.rawValue)).")
        }
        try verifyForeground(foreground)

        // Never set AXFocused: Chromium can bring its native window forward
        // asynchronously in response. The Search button's DOM handler selects
        // the input inside Spotify without requesting native window focus.
        guard let searchButton = spotifyAccessibilityElements(in: application, limit: rootTraversalLimit, matching: {
            stringAttribute(kAXRoleAttribute, of: $0) == kAXButtonRole && linkLabel($0) == "Search"
        }).first else {
            throw BackgroundControlError.accessibilityActionFailed("Spotify's Search button is unavailable.")
        }
        let pressResult = AXUIElementPerformAction(searchButton, kAXPressAction as CFString)
        guard pressResult == .success else {
            throw BackgroundControlError.accessibilityActionFailed("Spotify's Search button could not be pressed (\(pressResult.rawValue)).")
        }
        try verifyForeground(foreground)
        guard await waitForAccessibilityCondition(named: "search responder ready", timeout: .seconds(2), condition: {
            var focused: CFTypeRef?
            return AXUIElementCopyAttributeValue(field, kAXFocusedAttribute as CFString, &focused) == .success
                && (focused as? Bool) == true
                && stringAttribute(kAXValueAttribute, of: field) == query
        }) else {
            throw BackgroundControlError.accessibilityActionFailed("Spotify did not accept the search text.")
        }
        try verifyForeground(foreground)
        var pid: pid_t = 0
        guard AXUIElementGetPid(application, &pid) == .success, pid > 0,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) else {
            throw BackgroundControlError.accessibilityActionFailed("Could not submit the Spotify search.")
        }
        down.flags = []
        up.flags = []
        // Deliver exclusively to Spotify, never to the system keyboard stream
        // or the application where the user is working.
        down.postToPid(pid)
        up.postToPid(pid)
        logger.info("Submitted Spotify search directly to its background responder")
        try verifyForeground(foreground)
    }

    private func spotifySearchField(in application: AXUIElement) -> AXUIElement? {
        spotifyAccessibilityElements(in: application, limit: rootTraversalLimit) { element in
            let role = stringAttribute(kAXRoleAttribute, of: element)
            guard role == kAXComboBoxRole || role == kAXTextFieldRole else { return false }
            let label = stringAttribute(kAXDescriptionAttribute, of: element) ?? ""
            return label == "What do you want to play?" || label.localizedCaseInsensitiveContains("search")
        }.first
    }

    private func spotifyAccessibilityApplication() async throws -> AXUIElement {
        try await ensureSpotifyIsRunning()
        guard let spotify = NSRunningApplication.runningApplications(
            withBundleIdentifier: spotifyBundleID
        ).first else {
            throw BackgroundControlError.spotifyNotInstalled
        }

        let application = AXUIElementCreateApplication(spotify.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.5)
        return application
    }

    private func matchingSearchResult(
        for query: String,
        in application: AXUIElement
    ) -> SpotifyAccessibilitySearchResult? {
        let tables = spotifyAccessibilityElements(in: application, limit: rootTraversalLimit) {
            stringAttribute(kAXRoleAttribute, of: $0) == kAXTableRole
        }
        var best: SpotifyAccessibilitySearchResult?
        var bestScore = Int.min
        for table in tables {
            for row in accessibilityElements(in: table, limit: tableTraversalLimit)
                where stringAttribute(kAXRoleAttribute, of: row) == kAXRowRole {
                let rowElements = accessibilityElements(in: row, limit: rowTraversalLimit)
                let links = rowElements.filter {
                    stringAttribute(kAXRoleAttribute, of: $0) == "AXLink"
                }
                guard let track = links.first(where: { spotifyURI(of: $0, type: "track") != nil }),
                      let uri = spotifyURI(of: track, type: "track") else { continue }
                let artists = links.filter { spotifyURI(of: $0, type: "artist") != nil }.map(linkLabel)
                let identity = SpotifySearchIdentity(trackURI: uri, title: linkLabel(track), artists: artists)
                guard let score = identity.score(for: query), score > bestScore else { continue }
                guard let playButton = rowElements.first(where: {
                    guard stringAttribute(kAXRoleAttribute, of: $0) == kAXButtonRole else { return false }
                    let label = linkLabel($0)
                    return label == "Play" || label.hasPrefix("Play ")
                }) else { continue }
                best = SpotifyAccessibilitySearchResult(identity: identity, playButton: playButton)
                bestScore = score
            }
        }
        return best
    }

    private func spotifyURI(of element: AXUIElement, type: String) -> String? {
        for attribute in [kAXURLAttribute, kAXValueAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { continue }
            let text = (value as? URL)?.absoluteString ?? (value as? String)
            if let text, let uri = SpotifySearchIdentity.uri(from: text, type: type) { return uri }
        }
        return nil
    }

    private func linkLabel(_ element: AXUIElement) -> String {
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
            if let text = stringAttribute(attribute, of: element), !text.isEmpty,
               !text.contains("://") { return text }
        }
        return ""
    }

    private func logAccessibilitySummary(in application: AXUIElement) {
        let elements = spotifyAccessibilityRoots(in: application).flatMap {
            accessibilityElements(in: $0, limit: rootTraversalLimit)
        }
        let tables = elements.filter { stringAttribute(kAXRoleAttribute, of: $0) == kAXTableRole }.count
        let links = elements.filter { spotifyURI(of: $0, type: "track") != nil }.count
        logger.error("Spotify search timed out: elements=\(elements.count), tables=\(tables), trackLinks=\(links)")
    }

    private func spotifyAccessibilityElements(
        in application: AXUIElement,
        limit: Int,
        matching predicate: (AXUIElement) -> Bool
    ) -> [AXUIElement] {
        spotifyAccessibilityRoots(in: application).flatMap { root in
            accessibilityElements(in: root, limit: limit).filter(predicate)
        }
    }

    private func spotifyAccessibilityRoots(
        in application: AXUIElement
    ) -> [AXUIElement] {
        var roots: [AXUIElement] = []
        func append(_ root: AXUIElement) {
            guard !roots.contains(where: { CFEqual($0, root) }) else { return }
            roots.append(root)
        }

        if let focusedWindow = accessibilityElementAttribute(
            kAXFocusedWindowAttribute,
            of: application
        ) {
            append(focusedWindow)
        }
        if let mainWindow = accessibilityElementAttribute(
            kAXMainWindowAttribute,
            of: application
        ) {
            append(mainWindow)
        }
        for window in accessibilityWindows(in: application) {
            append(window)
        }
        if roots.isEmpty { append(application) }
        return roots
    }

    private func accessibilityWindows(
        in application: AXUIElement
    ) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private func accessibilityElementAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as! AXUIElement?
    }

    private func waitForAccessibilityElement<Element>(
        named name: String,
        timeout: Duration = .seconds(5),
        find: () -> Element?
    ) async -> Element? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var attempts = 0

        repeat {
            attempts += 1
            if let element = find() {
                logger.info("Found \(name) after \(attempts) attempt(s)")
                return element
            }
            try? await Task.sleep(for: accessibilityPollInterval)
        } while clock.now < deadline

        logger.info("Timed out waiting for \(name) after \(attempts) attempt(s)")
        return nil
    }

    private func waitForAccessibilityCondition(
        named name: String,
        timeout: Duration = .seconds(5),
        condition: () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var attempts = 0

        repeat {
            attempts += 1
            if condition() {
                logger.info("Verified \(name) after \(attempts) attempt(s)")
                return true
            }
            try? await Task.sleep(for: accessibilityPollInterval)
        } while clock.now < deadline

        logger.info("Timed out waiting for \(name) after \(attempts) attempt(s)")
        return false
    }

    private func accessibilityElements(
        in root: AXUIElement,
        limit: Int
    ) -> [AXUIElement] {
        var elements: [AXUIElement] = []
        var queue = [root]
        var index = 0

        while index < queue.count, elements.count < limit {
            let element = queue[index]
            index += 1
            elements.append(element)
            queue.append(contentsOf: accessibilityChildren(of: element))
        }
        return elements
    }

    private func accessibilityChildren(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private func stringAttribute(
        _ attribute: String,
        of element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    private func ensureSpotifyIsRunning() async throws {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: spotifyBundleID).isEmpty {
            return
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: spotifyBundleID
        ) else {
            throw BackgroundControlError.spotifyNotInstalled
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        _ = try await NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration
        )
        try? await Task.sleep(for: .seconds(3))
    }

    private func verifyForeground(_ expected: NSRunningApplication?) throws {
        guard let expected else { return }
        let current = NSWorkspace.shared.frontmostApplication
        guard current?.processIdentifier == expected.processIdentifier else {
            throw BackgroundControlError.foregroundChanged(
                expected.localizedName ?? expected.bundleIdentifier ?? "previous app",
                current?.localizedName ?? current?.bundleIdentifier ?? "unknown app"
            )
        }
    }
}

private struct SpotifyAccessibilitySearchResult {
    let identity: SpotifySearchIdentity
    let playButton: AXUIElement
}

private enum BackgroundControlError: LocalizedError {
    case spotifyNotInstalled
    case matchingTrackNotFound
    case accessibilityActionFailed(String)
    case playbackNotVerified(String)
    case foregroundChanged(String, String)

    var errorDescription: String? {
        switch self {
        case .spotifyNotInstalled:
            return "Spotify is not installed."
        case .matchingTrackNotFound:
            return "Spotify did not expose a matching playable track in its search results."
        case .accessibilityActionFailed(let evidence):
            return "Spotify could not complete the request: \(evidence)"
        case .playbackNotVerified(let query):
            return "Spotify did not expose matching playback for \(query)."
        case .foregroundChanged(let expected, let actual):
            return "Foreground changed from \(expected) to \(actual)."
        }
    }
}
