import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Combine

@MainActor
final class SpotifyBackgroundController: ObservableObject {
    static let shared = SpotifyBackgroundController()

    @Published private(set) var devices: [SpotifyDevice] = []
    @Published private(set) var currentDeviceName: String?
    @Published private(set) var isUpdatingDevices = false
    @Published private(set) var deviceError: String?

    private let spotifyBundleID = "com.spotify.client"
    private let logger = Logger.shared
    private var isRunning = false
    private let accessibilityPollInterval = Duration.milliseconds(250)
    private let searchNavigationTimeout = Duration.seconds(10)
    private let playbackTimeout = Duration.seconds(8)
    private let rootTraversalLimit = 6_000
    private let tableTraversalLimit = 2_000
    private let rowTraversalLimit = 100
    private let accessibilityMessageTimeout: Float = 0.5
    private var currentRunID = ""

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
        currentRunID = String(UUID().uuidString.prefix(8))
        let runID = currentRunID
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        let activationObserver = workspaceNotifications.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Logger.shared.warning("Spotify search run=\(runID) activationEventPID=\(app?.processIdentifier ?? 0) bundle=\(app?.bundleIdentifier ?? "unknown")")
        }
        let spaceObserver = workspaceNotifications.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Logger.shared.warning("Spotify search run=\(runID) activeSpaceChanged")
        }
        logger.info("Spotify search run=\(runID) started; queryChars=\(query.count); expectedForegroundPID=\(expectedForeground?.processIdentifier ?? 0)")
        Task {
            defer {
                workspaceNotifications.removeObserver(activationObserver)
                workspaceNotifications.removeObserver(spaceObserver)
                isRunning = false
                currentRunID = ""
            }
            do {
                if isUpdatingDevices {
                    logger.info("Spotify search run=\(runID) waiting for device work before Accessibility access")
                    try await Self.waitForDeviceWork(
                        isUpdating: { self.isUpdatingDevices }
                    )
                    logger.info("Spotify search run=\(runID) device work finished; continuing")
                }
                try verifyForeground(expectedForeground)
                let application = try await spotifyAccessibilityApplication()
                try verifyForeground(expectedForeground)
                try await submitSpotifySearch(query: query, in: application, preserving: expectedForeground)
                try verifyForeground(expectedForeground)

                guard let result = try await waitForSearchResult(
                    query: query, in: application, preserving: expectedForeground
                ) else {
                    logAccessibilitySummary(in: application, query: query)
                    throw BackgroundControlError.playableTrackNotFound
                }
                try verifyForeground(expectedForeground)
                logger.info("Spotify baseline result selectedTitle=\(result.selectedTitle) selectedArtist=\(result.selectedArtist) queryMatched=\(result.queryMatched) action=\(result.action.logDescription) selectedURI=\(result.trackURI)")
                // Play from the first result row that exactly matches the query. Spotify's
                // `play track` scripting command opens the track's album context and
                // can bring Spotify forward; the search-row action stays in search.
                try verifySearchText(query, in: application)
                switch result.action {
                case .play(let button):
                    let pressResult = AXUIElementPerformAction(
                        button,
                        kAXPressAction as CFString
                    )
                    guard pressResult == .success else {
                        throw BackgroundControlError.accessibilityActionFailed(
                            "Spotify's first song Play button could not be pressed (\(pressResult.rawValue))."
                        )
                    }
                    logger.info("Pressed Spotify first-song search-result Play button")
                case .verifyAlreadyPlaying:
                    logger.info("Matching Spotify result exposes Pause; verifying playback without pressing Pause")
                }
                try verifyForeground(expectedForeground)
                guard await waitForAccessibilityCondition(
                    named: "selected track playing",
                    timeout: playbackTimeout,
                    condition: { AppleScriptHelper.isSpotifyPlayingTrack(result.trackURI) }
                ) else {
                    throw BackgroundControlError.playbackNotVerified(query)
                }
                try verifyForeground(expectedForeground)
                logger.info("Spotify background playback verified; selectedTitle=\(result.selectedTitle) selectedURI=\(result.trackURI); foreground preserved")
            } catch {
                logger.error("Spotify background control failed", error: error)
            }
        }
    }

    func refreshDevices() {
        updateDevices(switchingTo: nil)
    }

    func switchDevice(_ device: SpotifyDevice) {
        guard !device.isCurrent else { return }
        updateDevices(switchingTo: device)
    }

    static func waitForDeviceWork(
        isUpdating: @MainActor () -> Bool,
        timeout: Duration = .seconds(30),
        pollingInterval: Duration = .milliseconds(100)
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while isUpdating() {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else {
                throw BackgroundControlError.accessibilityActionFailed(
                    "Spotify device work did not finish within 30 seconds; search was not submitted."
                )
            }
            try await Task.sleep(for: pollingInterval)
            try Task.checkCancellation()
            if isUpdating(), ContinuousClock.now >= deadline {
                throw BackgroundControlError.accessibilityActionFailed(
                    "Spotify device work did not finish within 30 seconds; search was not submitted."
                )
            }
        }
    }

    private func updateDevices(switchingTo requested: SpotifyDevice?) {
        guard !isUpdatingDevices else { return }
        guard !isRunning else {
            if requested != nil {
                deviceError = "Search is still finishing. Try again in a moment."
            }
            return
        }
        guard AXIsProcessTrusted() else {
            deviceError = "Allow Reflex in Accessibility settings to see Spotify devices."
            return
        }
        isUpdatingDevices = true
        deviceError = nil
        let foreground = NSWorkspace.shared.frontmostApplication
        Task {
            defer { isUpdatingDevices = false }
            do {
                let application = try await spotifyAccessibilityApplication()
                try verifyForeground(foreground)
                guard let window = spotifyAccessibilityRoots(in: application).first(where: {
                    devicePickerButton(in: $0) != nil
                }), let toggle = devicePickerButton(in: window) else {
                    throw BackgroundControlError.accessibilityActionFailed("Spotify's device picker is unavailable.")
                }
                let wasOpen = boolAttribute(kAXValueAttribute, of: toggle) == true
                defer {
                    // Restore only the panel that this request opened. Never
                    // activate Spotify or restore a different foreground app.
                    if !wasOpen, let button = devicePickerButton(in: window),
                       boolAttribute(kAXValueAttribute, of: button) == true {
                        try? press(button, named: "device picker")
                    }
                }
                if !wasOpen { try press(toggle, named: "device picker") }
                try await Task.sleep(for: .milliseconds(350))
                if (!wasOpen || readDevices(in: window) == nil), let field = spotifySearchField(in: window) {
                    // A second background action lets Spotify publish the new
                    // panel while its full-screen Space is inactive.
                    try press(field, named: "search field")
                }
                guard let picker = await waitForAccessibilityElement(
                    named: "Spotify devices", timeout: .seconds(8),
                    find: {
                        guard let button = self.devicePickerButton(in: window),
                              self.boolAttribute(kAXValueAttribute, of: button) == true else { return nil as SpotifyAccessibilityDevices? }
                        return self.readDevices(in: window)
                    }
                ) else {
                    throw BackgroundControlError.accessibilityActionFailed("Spotify's devices did not finish loading.")
                }
                try verifyForeground(foreground)
                publishDevices(picker)
                if let requested {
                    // Re-resolve against the live picker; never retain a row's
                    // Accessibility object across menu openings or reconnects.
                    guard let target = picker.options.first(where: { $0.device.id == requested.id }),
                          let button = target.button else {
                        throw BackgroundControlError.accessibilityActionFailed("That device is no longer available. Refresh devices and try again.")
                    }
                    if !target.device.isCurrent {
                        try press(button, named: "device")
                        try await Task.sleep(for: .milliseconds(350))
                        try verifyForeground(foreground)
                        if let field = spotifySearchField(in: window) {
                            // Spotify can complete a transfer while its hidden
                            // Accessibility snapshot still names the old device.
                            try press(field, named: "search field")
                        }
                        guard let confirmed = try await waitForDevice(
                            target.device.id, in: window, preserving: foreground
                        ) else {
                            throw BackgroundControlError.accessibilityActionFailed("Spotify did not confirm the device switch. Refresh devices to check.")
                        }
                        try verifyForeground(foreground)
                        publishDevices(confirmed)
                        logger.info("Spotify device switch verified; foreground preserved")
                    }
                }
                logger.info("Spotify devices refreshed; count=\(devices.count); foregroundPID=\(foreground?.processIdentifier ?? 0)")
            } catch {
                currentDeviceName = nil
                devices = []
                deviceError = error.localizedDescription
                logger.error("Spotify device control failed", error: error)
            }
        }
    }

    private func publishDevices(_ picker: SpotifyAccessibilityDevices) {
        currentDeviceName = picker.currentName
        devices = picker.options.map(\.device)
    }

    private func waitForDevice(
        _ deviceID: String, in window: AXUIElement, preserving foreground: NSRunningApplication?
    ) async throws -> SpotifyAccessibilityDevices? {
        let deadline = ContinuousClock.now.advanced(by: .seconds(12))
        repeat {
            try verifyForeground(foreground)
            if let result = readDevices(in: window),
               result.options.contains(where: { $0.device.isCurrent && $0.device.id == deviceID }) {
                return result
            }
            // The Connect transfer finishes asynchronously. Keep requesting a
            // fresh hidden-window update until Spotify names the new device;
            // one action immediately after the click can be too early.
            if let field = spotifySearchField(in: window) {
                try press(field, named: "search field")
            }
            try await Task.sleep(for: .milliseconds(500))
        } while ContinuousClock.now < deadline
        return nil
    }

    private func devicePickerButton(in window: AXUIElement) -> AXUIElement? {
        accessibilityElements(in: window, limit: rootTraversalLimit).first {
            guard linkLabel($0) == "Connect to a device" else { return false }
            // Chromium exposes aria-pressed controls as toggle buttons rather
            // than ordinary AXButtons. Match the supported action, not a role.
            var actions: CFArray?
            return AXUIElementCopyActionNames($0, &actions) == .success
                && (actions as? [String] ?? []).contains(kAXPressAction)
        }
    }

    private func readDevices(in window: AXUIElement) -> SpotifyAccessibilityDevices? {
        guard let panel = accessibilityElements(in: window, limit: rootTraversalLimit).first(where: {
            stringAttribute(kAXRoleAttribute, of: $0) == kAXGroupRole && linkLabel($0) == "Connect to a device"
        }) else { return nil }
        let elements = accessibilityElements(in: panel, limit: 500)
        guard let current = elements.first(where: { linkLabel($0) == "Current device" }),
              let name = accessibilityChildren(of: current).map({ linkLabel($0) }).first(where: {
                  !$0.isEmpty && $0 != "Listen with friends anywhere"
              }) else { return nil }
        let isLocal = name == "This computer" || accessibilityElements(in: current, limit: 30)
            .contains { linkLabel($0) == "This computer" }
        var options = [SpotifyAccessibilityDevice(
            device: SpotifyDevice(id: isLocal ? "local" : "name:\(name)", name: name, isCurrent: true), button: nil
        )]
        for list in elements where stringAttribute(kAXRoleAttribute, of: list) == kAXListRole {
            guard linkLabel(list) != "No other devices found" else { continue }
            for row in accessibilityChildren(of: list) {
                let buttons = accessibilityElements(in: row, limit: 80).filter {
                    stringAttribute(kAXRoleAttribute, of: $0) == kAXButtonRole
                        && boolAttribute(kAXEnabledAttribute, of: $0) != false
                }
                guard let button = buttons.first,
                      !linkLabel(button).isEmpty else { continue }
                let deviceName = linkLabel(button)
                let deviceID = deviceName == "This computer" ? "local" : "name:\(deviceName)"
                // Current device and available rows update separately during a
                // transfer. A device cannot be current and available at once;
                // wait for the complete new snapshot instead of dropping a row.
                guard deviceID != options[0].device.id else { return nil }
                options.append(SpotifyAccessibilityDevice(
                    device: SpotifyDevice(id: deviceID, name: deviceName, isCurrent: false), button: button
                ))
            }
        }
        // An indistinguishable duplicate is unsafe to target by name.
        let counts = Dictionary(grouping: options, by: { $0.device.id }).mapValues(\.count)
        options.removeAll { counts[$0.device.id, default: 0] > 1 }
        return SpotifyAccessibilityDevices(currentName: name, options: options)
    }

    private func boolAttribute(_ attribute: String, of element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private func submitSpotifySearch(
        query: String,
        in application: AXUIElement,
        preserving foreground: NSRunningApplication?
    ) async throws {
        // Spotify's URL handler activates its window even when Launch Services
        // receives activates=false. Never use a search URL here, including as a fallback.
        try verifyForeground(foreground)
        try pressSearchButton(in: application)
        try verifyForeground(foreground)
        guard let field = await waitForAccessibilityElement(
            named: "Spotify search field", timeout: searchNavigationTimeout,
            find: { spotifySearchField(in: application) }
        ) else {
            throw BackgroundControlError.accessibilityActionFailed("Spotify's search field is unavailable.")
        }
        try verifyForeground(foreground)

        var pid: pid_t = 0
        AXUIElementGetPid(application, &pid)
        let currentValue = stringAttribute(kAXValueAttribute, of: field) ?? ""
        var range = CFRange(location: 0, length: currentValue.utf16.count)
        let selectedRange = AXValueCreate(.cfRange, &range)!
        let selectionResult = AXUIElementSetAttributeValue(
            field, kAXSelectedTextRangeAttribute as CFString, selectedRange
        )
        logger.info("Spotify selection result=\(selectionResult.rawValue)")

        try verifyForeground(foreground)
        guard AXUIElementGetPid(application, &pid) == .success, pid > 0,
              let source = CGEventSource(stateID: .privateState) else {
            throw BackgroundControlError.accessibilityActionFailed("Could not create Spotify's Unicode search input events.")
        }
        logger.info("Spotify input access preflight AXTrusted=\(AXIsProcessTrusted()) postEvent=\(CGPreflightPostEventAccess())")
        var postedScalarCount = 0
        for scalar in query.unicodeScalars {
            let scalarUTF16 = Array(String(scalar).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                throw BackgroundControlError.accessibilityActionFailed("Could not create Spotify's Unicode search input events.")
            }
            down.flags = []
            up.flags = []
            scalarUTF16.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            down.postToPid(pid)
            up.postToPid(pid)
            postedScalarCount += 1
        }
        logger.info("Spotify Unicode scalar input postedToPID=\(pid) scalarCount=\(postedScalarCount)")
        guard let searchButton = spotifyAccessibilityElements(in: application, limit: rootTraversalLimit, matching: {
            stringAttribute(kAXRoleAttribute, of: $0) == kAXButtonRole && linkLabel($0) == "Search"
        }).first else {
            throw BackgroundControlError.accessibilityActionFailed("Spotify's Search button is unavailable.")
        }
        let submitPress = AXUIElementPerformAction(searchButton, kAXPressAction as CFString)
        logger.info("Spotify post-input Search press=\(submitPress.rawValue)")
        let refreshedField = spotifySearchField(in: application)
        logger.info("Spotify search run=\(currentRunID) fieldSurvivedSearchPress=\(refreshedField.map { CFEqual($0, field) } ?? false)")
        try verifyForeground(foreground)
        guard let retryButton = spotifyAccessibilityElements(in: application, limit: rootTraversalLimit, matching: {
            stringAttribute(kAXRoleAttribute, of: $0) == kAXButtonRole && linkLabel($0) == "Search"
        }).first else {
            throw BackgroundControlError.accessibilityActionFailed("Spotify's Search button is unavailable.")
        }
        let retryPress = AXUIElementPerformAction(retryButton, kAXPressAction as CFString)
        logger.info("Spotify repeated Search press=\(retryPress.rawValue)")
    }

    private func waitForSearchResult(
        query: String, in application: AXUIElement, preserving foreground: NSRunningApplication?
    ) async throws -> SpotifyAccessibilitySearchResult? {
        let deadline = ContinuousClock.now.advanced(by: searchNavigationTimeout)
        repeat {
            try verifyForeground(foreground)
            if let result = firstPlayableSongResult(for: query, in: application) { return result }
            try verifySearchText(query, in: application)
            // Hidden Chromium windows can publish input, results and route in separate updates.
            // Resubmit only while the exact query remains in the search field.
            try pressSearchButton(in: application)
            try await Task.sleep(for: .milliseconds(500))
            try verifyForeground(foreground)
            try verifySearchText(query, in: application)
            try postSearchReturn(to: application)
            try await Task.sleep(for: .milliseconds(500))
        } while ContinuousClock.now < deadline
        return nil
    }

    private func verifySearchText(_ query: String, in application: AXUIElement) throws {
        guard let field = spotifySearchField(in: application),
              normalizedSearchQuery(stringAttribute(kAXValueAttribute, of: field) ?? "") == normalizedSearchQuery(query) else {
            throw BackgroundControlError.accessibilityActionFailed("Spotify's search text changed before submission.")
        }
    }

    private func pressSearchButton(in application: AXUIElement) throws {
        guard let button = spotifyAccessibilityElements(in: application, limit: rootTraversalLimit, matching: {
            stringAttribute(kAXRoleAttribute, of: $0) == kAXButtonRole && linkLabel($0) == "Search"
        }).first else {
            throw BackgroundControlError.accessibilityActionFailed("Spotify's Search button is unavailable.")
        }
        try press(button, named: "Search button")
    }

    private func postSearchReturn(to application: AXUIElement) throws {
        var pid: pid_t = 0
        guard AXUIElementGetPid(application, &pid) == .success, pid > 0,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) else {
            throw BackgroundControlError.accessibilityActionFailed("Could not submit the Spotify search.")
        }
        down.flags = []
        up.flags = []
        down.postToPid(pid)
        up.postToPid(pid)
    }

    private func press(_ element: AXUIElement, named name: String) throws {
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard result == .success else {
            throw BackgroundControlError.accessibilityActionFailed(
                "Spotify's \(name) could not be pressed (\(result.rawValue))."
            )
        }
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
        AXUIElementSetMessagingTimeout(application, accessibilityMessageTimeout)
        return application
    }

    private func firstPlayableSongResult(
        for query: String,
        in application: AXUIElement
    ) -> SpotifyAccessibilitySearchResult? {
        let started = ContinuousClock.now
        var matches: [SpotifyAccessibilitySearchResult] = []
        for root in spotifyAccessibilityRoots(in: application) {
            let elements = accessibilityElements(in: root, limit: rootTraversalLimit)
            let field = elements.first { element in
                let role = stringAttribute(kAXRoleAttribute, of: element)
                guard role == kAXComboBoxRole || role == kAXTextFieldRole else { return false }
                let label = stringAttribute(kAXDescriptionAttribute, of: element) ?? ""
                return label == "What do you want to play?" || label.localizedCaseInsensitiveContains("search")
            }
            guard let field,
                  normalizedSearchQuery(stringAttribute(kAXValueAttribute, of: field) ?? "")
                    == normalizedSearchQuery(query) else { continue }

            let tables = elements.filter {
                stringAttribute(kAXRoleAttribute, of: $0) == kAXTableRole
                    && linkLabel($0) == "Search results"
            }
            for table in tables {
                for row in accessibilityElements(in: table, limit: tableTraversalLimit)
                    where stringAttribute(kAXRoleAttribute, of: row) == kAXRowRole {
                    let rowElements = accessibilityElements(in: row, limit: rowTraversalLimit)
                    let links = rowElements.filter {
                        stringAttribute(kAXRoleAttribute, of: $0) == "AXLink"
                    }
                    let trackLinks = links.compactMap { element -> (AXUIElement, String)? in
                        guard let uri = spotifyURI(of: element, type: "track") else { return nil }
                        return (element, uri)
                    }
                    let distinctTrackURIs = Set(trackLinks.map(\.1))
                    guard distinctTrackURIs.count == 1,
                          let (track, uri) = trackLinks.first else { continue }

                    var artists: [String] = []
                    for artistLink in links where spotifyURI(of: artistLink, type: "artist") != nil {
                        let label = linkLabel(artistLink)
                        if !label.isEmpty && !artists.contains(label) { artists.append(label) }
                    }
                    guard !artists.isEmpty,
                          !linkLabel(track).isEmpty,
                          let identity = SpotifySearchIdentity.normalizedIdentity(
                            title: linkLabel(track), artists: artists
                          ) else { continue }
                    let matchKind = SpotifySearchIdentity.searchQueryMatchKind(
                        query, title: linkLabel(track), artists: artists
                    )
                    let queryMatched = matchKind != nil
                    guard queryMatched, let matchKind else { continue }
                    let rowButtons = rowElements.filter {
                        stringAttribute(kAXRoleAttribute, of: $0) == kAXButtonRole
                    }
                    let buttonLabels = rowButtons.map(linkLabel)
                    guard let actionKind = SpotifySearchResultActionKind.classify(buttonLabels: buttonLabels) else {
                        continue
                    }
                    let action: SpotifyAccessibilitySearchResultAction
                    switch actionKind {
                    case .play:
                        guard let playButton = rowButtons.first(where: {
                            let label = linkLabel($0)
                            return label == "Play" || label.hasPrefix("Play ")
                        }) else { continue }
                        action = .play(playButton)
                    case .verifyAlreadyPlaying:
                        action = .verifyAlreadyPlaying
                    }

                    matches.append(SpotifyAccessibilitySearchResult(
                        trackURI: uri,
                        selectedTitle: linkLabel(track),
                        selectedArtist: artists.joined(separator: ", "),
                        queryMatched: queryMatched,
                        matchKind: matchKind,
                        normalizedIdentity: identity,
                        action: action
                    ))
                }
            }
        }
        let elapsed = ContinuousClock.now - started
        if elapsed > .seconds(1) {
            logger.warning("Spotify result traversal took \(elapsed); matchingRows=\(matches.count)")
        }
        guard !matches.isEmpty else { return nil }

        let matchKinds = matches.map(\.matchKind)
        let identities = matches.map(\.normalizedIdentity)
        guard let selectedIndex = SpotifySearchIdentity.selectedMatchIndex(
            matchKinds: matchKinds, normalizedIdentities: identities
        ) else {
            if matchKinds.contains(.titleAndArtist) {
                logger.warning("Spotify query rejected ambiguous result identities")
            }
            return nil
        }
        // Exact title-only and artist-only queries keep Spotify's result ranking.
        return matches[selectedIndex]
    }

    private func searchRoute(of element: AXUIElement, matches query: String) -> Bool {
        guard stringAttribute(kAXRoleAttribute, of: element) == "AXLink" else { return false }
        let requestedQuery = normalizedSearchQuery(query)
        for attribute in [kAXURLAttribute, kAXValueAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { continue }
            let text = (value as? URL)?.absoluteString ?? (value as? String)
            if let text,
               let routedQuery = SpotifySearchIdentity.searchQuery(from: text),
               normalizedSearchQuery(routedQuery) == requestedQuery {
                return true
            }
        }
        return false
    }

    private func normalizedSearchQuery(_ query: String) -> String {
        query.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
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

    private func logAccessibilitySummary(in application: AXUIElement, query: String) {
        let elements = spotifyAccessibilityRoots(in: application).flatMap {
            accessibilityElements(in: $0, limit: rootTraversalLimit)
        }
        let tables = elements.filter { stringAttribute(kAXRoleAttribute, of: $0) == kAXTableRole }.count
        for table in elements where stringAttribute(kAXRoleAttribute, of: table) == kAXTableRole && linkLabel(table) == "Search results" {
            let rows = accessibilityElements(in: table, limit: tableTraversalLimit).filter {
                stringAttribute(kAXRoleAttribute, of: $0) == kAXRowRole
            }
            logger.info("Spotify result row labels=\(rows.prefix(5).map { linkLabel($0) }.joined(separator: " | "))")
        }
        let links = elements.filter { spotifyURI(of: $0, type: "track") != nil }.count
        let routeMatches = elements.contains { searchRoute(of: $0, matches: query) }
        let fieldMatches = elements.first(where: {
            let role = stringAttribute(kAXRoleAttribute, of: $0)
            return role == kAXComboBoxRole && stringAttribute(kAXDescriptionAttribute, of: $0) == "What do you want to play?"
        }).map { stringAttribute(kAXValueAttribute, of: $0) == query } ?? false
        logger.error("Spotify search run=\(currentRunID) timed out: elements=\(elements.count), tables=\(tables), trackLinks=\(links), routeMatches=\(routeMatches), fieldMatches=\(fieldMatches)")
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
            // AX messaging timeouts belong to individual element objects, not
            // to the application and all of its descendants.
            AXUIElementSetMessagingTimeout(element, accessibilityMessageTimeout)
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

struct SpotifyDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let isCurrent: Bool
}

private struct SpotifyAccessibilityDevice {
    let device: SpotifyDevice
    let button: AXUIElement?
}

private struct SpotifyAccessibilityDevices {
    let currentName: String
    let options: [SpotifyAccessibilityDevice]
}

private struct SpotifyAccessibilitySearchResult {
    let trackURI: String
    let selectedTitle: String
    let selectedArtist: String
    let queryMatched: Bool
    let matchKind: SpotifySearchIdentity.SearchQueryMatchKind
    let normalizedIdentity: String
    let action: SpotifyAccessibilitySearchResultAction
}

enum SpotifySearchResultActionKind: Equatable {
    case play
    case verifyAlreadyPlaying

    static func classify(buttonLabels: [String]) -> SpotifySearchResultActionKind? {
        if buttonLabels.contains(where: { $0 == "Play" || $0.hasPrefix("Play ") }) {
            return .play
        }
        if buttonLabels.contains(where: { $0 == "Pause" || $0.hasPrefix("Pause ") }) {
            return .verifyAlreadyPlaying
        }
        return nil
    }
}

private enum SpotifyAccessibilitySearchResultAction {
    case play(AXUIElement)
    case verifyAlreadyPlaying

    var logDescription: String {
        switch self {
        case .play: return "play"
        case .verifyAlreadyPlaying: return "verifyAlreadyPlaying"
        }
    }
}

private enum BackgroundControlError: LocalizedError {
    case spotifyNotInstalled
    case playableTrackNotFound
    case accessibilityActionFailed(String)
    case playbackNotVerified(String)
    case foregroundChanged(String, String)

    var errorDescription: String? {
        switch self {
        case .spotifyNotInstalled:
            return "Spotify is not installed."
        case .playableTrackNotFound:
            return "Spotify did not expose a playable song in its search results."
        case .accessibilityActionFailed(let evidence):
            return "Spotify could not complete the request: \(evidence)"
        case .playbackNotVerified(let query):
            return "Spotify did not expose matching playback for \(query)."
        case .foregroundChanged(let expected, let actual):
            return "Foreground changed from \(expected) to \(actual)."
        }
    }
}
