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
    private let searchAttempts = 3
    private let returnKeyCode: CGKeyCode = 36
    private let accessibilityPollInterval = Duration.milliseconds(250)
    private let foregroundPollInterval = Duration.milliseconds(50)
    private let searchFieldTimeout = Duration.seconds(10)
    private let searchResultsTimeout = Duration.seconds(4)
    private let playbackTimeout = Duration.seconds(5)
    private let rootTraversalLimit = 6_000
    private let tableTraversalLimit = 2_000
    private let rowTraversalLimit = 100

    private init() {}

    func play(query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isRunning else { return }
        guard AXIsProcessTrusted() else {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
            logger.error("Spotify background control requires Accessibility permission")
            return
        }

        isRunning = true
        NSApp.hide(nil)

        Task {
            defer { isRunning = false }

            do {
                guard let expectedForeground = await waitForForegroundApplication(
                    excluding: Bundle.main.bundleIdentifier,
                    timeout: .seconds(2)
                ) else {
                    throw BackgroundControlError.foregroundNotRestored
                }
                guard expectedForeground.bundleIdentifier != spotifyBundleID else {
                    throw BackgroundControlError.spotifyWasForeground
                }
                let evidence = try await execute(
                    query: query,
                    expectedForeground: expectedForeground
                )
                logger.info("Spotify background control passed: \(evidence)")
            } catch {
                logger.error("Spotify background control failed", error: error)
            }
        }
    }

    private func execute(
        query: String,
        expectedForeground: NSRunningApplication?
    ) async throws -> String {
        let application = try await spotifyAccessibilityApplication()
        try verifyForeground(expectedForeground)

        guard let spotify = NSRunningApplication.runningApplications(
            withBundleIdentifier: spotifyBundleID
        ).first else {
            throw BackgroundControlError.spotifyNotInstalled
        }

        var selectedResult: SpotifySearchResult?
        for searchAttempt in 1...searchAttempts {
            guard let searchField = await waitForAccessibilityElement(
                named: "Spotify search field",
                timeout: searchFieldTimeout,
                find: { spotifySearchField(in: application) }
            ) else {
                throw BackgroundControlError.searchFieldNotWritable
            }
            try setAccessibilityValue(query, on: searchField)
            logger.info(
                "Set Spotify search field through Accessibility: query=\(query), attempt=\(searchAttempt)"
            )
            try verifyForeground(expectedForeground)

            let focusResult = AXUIElementSetAttributeValue(
                searchField,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
            logger.info(
                "Refocused Spotify search field: result=\(focusResult.rawValue)"
            )
            _ = await waitForAccessibilityCondition(
                named: "Spotify search field value",
                timeout: .seconds(1),
                condition: {
                    normalizedText(
                        stringAttribute(kAXValueAttribute, of: searchField) ?? ""
                    ) == normalizedText(query)
                }
            )
            await postKey(returnKeyCode, to: spotify.processIdentifier)
            try verifyForeground(expectedForeground)

            if playbackMatches(
                tokens: queryTokens(query),
                requireAllTokens: true,
                in: application
            ) {
                return "Spotify was already playing the matching song."
            }
            if let found = await waitForAccessibilityElement(
                named: "matching Spotify Play button",
                timeout: searchResultsTimeout,
                find: { matchingSearchResult(for: query, in: application) }
            ) {
                selectedResult = found
                break
            }
            logger.info(
                "Spotify search results did not match after submission attempt \(searchAttempt)"
            )
        }

        guard let selectedResult else {
            throw BackgroundControlError.matchingPlayButtonNotFound(query)
        }

        guard let currentResult = await waitForAccessibilityElement(
            named: "current matching Spotify Play button",
            timeout: searchResultsTimeout,
            find: {
                matchingSearchResult(
                    for: query,
                    matching: selectedResult.identityTokens,
                    in: application
                )
            }
        ) else {
            throw BackgroundControlError.matchingPlayButtonNotFound(query)
        }

        try pressAccessibilityElement(
            currentResult.playButton,
            description: currentResult.buttonDescription
        )
        try verifyForeground(expectedForeground)
        guard await waitForAccessibilityCondition(
            named: "matching Spotify playback after Accessibility press",
            timeout: playbackTimeout,
            condition: {
                playbackMatches(
                    tokens: currentResult.identityTokens,
                    in: application
                )
            }
        ) else {
            throw BackgroundControlError.playbackNotVerified(query)
        }

        return "Pressed \(currentResult.buttonDescription) and verified matching playback."
    }

    private func spotifyAccessibilityApplication() async throws -> AXUIElement {
        try await ensureSpotifyIsRunning()
        guard let spotify = NSRunningApplication.runningApplications(
            withBundleIdentifier: spotifyBundleID
        ).first else {
            throw BackgroundControlError.spotifyNotInstalled
        }

        let application = AXUIElementCreateApplication(spotify.processIdentifier)
        let enableResult = AXUIElementSetAttributeValue(
            application,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )
        logger.info(
            "Enabled Spotify manual Accessibility: result=\(enableResult.rawValue), windows=\(accessibilityWindows(in: application).count)"
        )
        return application
    }

    private func spotifySearchField(in application: AXUIElement) -> AXUIElement? {
        firstSpotifyAccessibilityElement(
            in: application,
            limit: rootTraversalLimit
        ) { element in
            let role = stringAttribute(kAXRoleAttribute, of: element)
            guard role == kAXComboBoxRole || role == kAXTextFieldRole else {
                return false
            }
            let text = normalizedText(elementText(element))
            return text.contains("what do you want to play") ||
                text.contains("search")
        }
    }

    private func matchingSearchResult(
        for query: String,
        matching expectedIdentityTokens: [String]? = nil,
        in application: AXUIElement
    ) -> SpotifySearchResult? {
        let queryText = normalizedText(query)
        let tokens = queryTokens(query)
        let minimumTokenMatches = max(1, Int(ceil(Double(tokens.count) * 0.6)))
        var bestResult: SpotifySearchResult?
        var bestScore = 0

        let resultsTables = spotifyAccessibilityElements(
            in: application,
            limit: rootTraversalLimit,
            matching: {
                stringAttribute(kAXRoleAttribute, of: $0) == kAXTableRole &&
                    normalizedText(elementText($0)).contains("search results")
            }
        )

        for resultsTable in resultsTables {
            for row in accessibilityElements(in: resultsTable, limit: tableTraversalLimit) {
                guard stringAttribute(kAXRoleAttribute, of: row) == kAXRowRole else {
                    continue
                }
                let rowElements = accessibilityElements(in: row, limit: rowTraversalLimit)
                let contentText = normalizedText(
                    rowElements
                        .filter {
                            stringAttribute(kAXRoleAttribute, of: $0) != kAXButtonRole
                        }
                        .map(elementText)
                        .joined(separator: " ")
                )
                let rowWords = contentText.components(separatedBy: " ")
                let tokenMatches = tokens.filter(rowWords.contains).count
                guard tokenMatches >= minimumTokenMatches else { continue }

                guard let playButton = rowElements.first(where: {
                    guard stringAttribute(kAXRoleAttribute, of: $0) == kAXButtonRole else {
                        return false
                    }
                    let text = normalizedText(elementText($0))
                    return text == "play" || text.hasPrefix("play ")
                }) else {
                    continue
                }
                let playText = normalizedText(elementText(playButton))
                let isTopResultButton = playText == "play"
                guard rowWords.contains("song") || isTopResultButton else {
                    continue
                }

                let identityTokens = resultIdentityTokens(
                    rowElements: rowElements,
                    fallback: tokens
                )
                let identityScore: Int
                if let expectedIdentityTokens {
                    identityScore = tokenOverlap(
                        identityTokens,
                        expectedIdentityTokens
                    )
                    guard identityScore >= minimumIdentityMatches(
                        for: expectedIdentityTokens
                    ) else {
                        continue
                    }
                } else {
                    identityScore = 0
                }

                let score = tokenMatches +
                    identityScore * 100 +
                    (contentText.contains(queryText) ? 1_000 : 0) +
                    (isTopResultButton ? 2_000 : 0)
                if score > bestScore {
                    bestScore = score
                    bestResult = SpotifySearchResult(
                        playButton: playButton,
                        buttonDescription: elementText(playButton),
                        identityTokens: identityTokens
                    )
                }
            }
        }

        return bestResult
    }

    private func playbackMatches(
        tokens: [String],
        requireAllTokens: Bool = false,
        in application: AXUIElement
    ) -> Bool {
        guard let requiredToken = tokens.first else { return false }
        let minimumTokenMatches = requireAllTokens
            ? tokens.count
            : minimumIdentityMatches(for: tokens)

        return firstSpotifyAccessibilityElement(
            in: application,
            limit: rootTraversalLimit
        ) { element in
            let text = normalizedText(elementText(element))
            guard text.hasPrefix("pause ") || text.hasPrefix("now playing ") else {
                return false
            }
            let words = text.components(separatedBy: " ")
            return words.contains(requiredToken) &&
                tokens.filter(words.contains).count >= minimumTokenMatches
        } != nil
    }

    private func setAccessibilityValue(
        _ value: String,
        on element: AXUIElement
    ) throws {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &settable
        ) == .success, settable.boolValue else {
            throw BackgroundControlError.searchFieldNotWritable
        }

        _ = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        let result = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            value as CFString
        )
        guard result == .success else {
            throw BackgroundControlError.accessibilityActionFailed(
                "Setting the search field returned \(result.rawValue)."
            )
        }
    }

    private func pressAccessibilityElement(
        _ element: AXUIElement,
        description: String
    ) throws {
        let result = AXUIElementPerformAction(
            element,
            kAXPressAction as CFString
        )
        logger.info(
            "Accessibility press: element=\(description), result=\(result.rawValue)"
        )
        guard result == .success else {
            throw BackgroundControlError.accessibilityActionFailed(
                "Pressing \(description) returned \(result.rawValue)."
            )
        }
    }

    private func firstAccessibilityElement(
        in root: AXUIElement,
        limit: Int,
        matching predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        accessibilityElements(in: root, limit: limit).first(where: predicate)
    }

    private func firstSpotifyAccessibilityElement(
        in application: AXUIElement,
        limit: Int,
        matching predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        for root in spotifyAccessibilityRoots(in: application) {
            if let element = firstAccessibilityElement(
                in: root,
                limit: limit,
                matching: predicate
            ) {
                return element
            }
        }
        return nil
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

    private func elementText(_ element: AXUIElement) -> String {
        [
            stringAttribute(kAXTitleAttribute, of: element),
            stringAttribute(kAXDescriptionAttribute, of: element),
            stringAttribute(kAXValueAttribute, of: element),
            stringAttribute(kAXHelpAttribute, of: element)
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
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

    private func normalizedText(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func queryTokens(_ query: String) -> [String] {
        let queryWords = Set(normalizedText(query).components(separatedBy: " "))
        return tokens(
            in: query,
            ignoring: ["a", "an", "and", "by", "feat", "featuring", "the", "with"],
            allowingSingleCharacterTokens: queryWords
        )
    }

    private func resultIdentityTokens(
        rowElements: [AXUIElement],
        fallback: [String]
    ) -> [String] {
        let identityText = rowElements
            .filter {
                stringAttribute(kAXRoleAttribute, of: $0) == kAXStaticTextRole
            }
            .map(elementText)
            .joined(separator: " ")
        let queryTokenSet = Set(fallback)
        let ignoredUITokens = Set(["play", "song", "top", "result", "button"])
            .subtracting(queryTokenSet)
        let tokens = tokens(
            in: identityText,
            ignoring: Set([
                "a", "an", "and", "by", "feat", "featuring", "the", "with"
            ]).union(ignoredUITokens),
            allowingSingleCharacterTokens: queryTokenSet
        )
        return tokens.isEmpty ? fallback : tokens
    }

    private func tokens(
        in text: String,
        ignoring ignored: Set<String>,
        allowingSingleCharacterTokens allowedSingleCharacterTokens: Set<String>
    ) -> [String] {
        var seen = Set<String>()
        return normalizedText(text)
            .components(separatedBy: " ")
            .filter {
                ($0.count > 1 || allowedSingleCharacterTokens.contains($0)) &&
                    !ignored.contains($0) &&
                    seen.insert($0).inserted
            }
    }

    private func tokenOverlap(_ lhs: [String], _ rhs: [String]) -> Int {
        let rhs = Set(rhs)
        return lhs.filter(rhs.contains).count
    }

    private func minimumIdentityMatches(for tokens: [String]) -> Int {
        max(1, Int(ceil(Double(tokens.count) * 0.6)))
    }

    private func ensureSpotifyIsRunning() async throws {
        if let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: spotifyBundleID
        ).first {
            if application.isHidden {
                _ = application.unhide()
            }
            unminimizeWindows(for: application.processIdentifier)
            try? await Task.sleep(for: .milliseconds(500))
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

    private func unminimizeWindows(for processID: pid_t) {
        let application = AXUIElementCreateApplication(processID)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success, let windows = value as? [AXUIElement] else {
            return
        }

        for window in windows {
            _ = AXUIElementSetAttributeValue(
                window,
                kAXMinimizedAttribute as CFString,
                kCFBooleanFalse
            )
        }
    }

    private func postKey(_ virtualKey: CGKeyCode, to processID: pid_t) async {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(
            keyboardEventSource: source,
            virtualKey: virtualKey,
            keyDown: true
        )
        let up = CGEvent(
            keyboardEventSource: source,
            virtualKey: virtualKey,
            keyDown: false
        )
        down?.postToPid(processID)
        try? await Task.sleep(for: .milliseconds(80))
        up?.postToPid(processID)
        logger.info(
            "Posted background key to Spotify: keyCode=\(virtualKey), pid=\(processID)"
        )
    }

    private func waitForForegroundApplication(
        excluding bundleIdentifier: String?,
        timeout: Duration
    ) async -> NSRunningApplication? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        repeat {
            if let application = NSWorkspace.shared.frontmostApplication,
               application.bundleIdentifier != bundleIdentifier {
                return application
            }
            try? await Task.sleep(for: foregroundPollInterval)
        } while clock.now < deadline

        return nil
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

private struct SpotifySearchResult {
    let playButton: AXUIElement
    let buttonDescription: String
    let identityTokens: [String]
}

private enum BackgroundControlError: LocalizedError {
    case spotifyNotInstalled
    case spotifyWasForeground
    case foregroundNotRestored
    case searchFieldNotWritable
    case matchingPlayButtonNotFound(String)
    case accessibilityActionFailed(String)
    case playbackNotVerified(String)
    case foregroundChanged(String, String)

    var errorDescription: String? {
        switch self {
        case .spotifyNotInstalled:
            return "Spotify is not installed."
        case .spotifyWasForeground:
            return "Spotify was the foreground app when background control started."
        case .foregroundNotRestored:
            return "Reflex could not restore the previous foreground app."
        case .searchFieldNotWritable:
            return "Spotify did not expose a writable search field."
        case .matchingPlayButtonNotFound(let query):
            return "Spotify did not expose a matching Play button for \(query)."
        case .accessibilityActionFailed(let evidence):
            return "Spotify’s Accessibility action failed: \(evidence)"
        case .playbackNotVerified(let query):
            return "Spotify did not expose matching playback for \(query)."
        case .foregroundChanged(let expected, let actual):
            return "Foreground changed from \(expected) to \(actual)."
        }
    }
}
