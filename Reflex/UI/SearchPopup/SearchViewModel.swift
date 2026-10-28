import Foundation
import Combine
import AppKit

enum SearchPopupState: Equatable {
    case idle
    case commands([SearchCommandItem])
}

enum SearchCommandKind: String, Hashable {
    case restartCurrentTrack
    case sleepTimer5Minutes
    case sleepTimer10Minutes
    case sleepTimer15Minutes
    case sleepTimer30Minutes
    case sleepTimer45Minutes
    case sleepTimer1Hour
    case sleepTimerEndOfTrack
    case goToTrack
    case goToAlbum
    case goToArtist
}

struct SearchCommandItem: Identifiable, Equatable {
    let kind: SearchCommandKind
    let title: String
    let subtitle: String
    let systemImage: String
    let isEnabled: Bool
    let sortTitle: String

    var id: SearchCommandKind { kind }

    init(kind: SearchCommandKind,
         title: String,
         subtitle: String,
         systemImage: String,
         isEnabled: Bool,
         sortTitle: String? = nil) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.sortTitle = sortTitle ?? title
    }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var selectedIndex: Int = 0
    @Published var state: SearchPopupState = .idle
    @Published var toast: String?

    private let stateManager: PlaybackStateManager?
    private let commandPrefix = ">"
    private let commandUsageKey = "search.commands.recentUse"

    private var toastTask: Task<Void, Never>?
    private var sleepTimerTask: Task<Void, Never>?

    init(stateManager: PlaybackStateManager? = nil) {
        self.stateManager = stateManager
    }

    func reset() {
        toastTask?.cancel()
        toastTask = nil
        toast = nil
        query = ""
        selectedIndex = 0
        state = .idle
    }

    private func showToast(_ message: String, duration: TimeInterval = 1.6, closeAfterToast: Bool = false) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if Task.isCancelled { return }
            guard let self else { return }
            await MainActor.run {
                if closeAfterToast {
                    SearchPopupController.shared.close(restoreFocus: true)
                } else {
                    self.toast = nil
                }
            }
        }
    }

    func onQueryChanged(_ newValue: String) {
        query = newValue

        if isCommandQuery(newValue) {
            updateCommandResults(for: newValue)
            return
        }

        selectedIndex = 0
        state = .idle
    }

    func moveSelection(by delta: Int) {
        guard case .commands(let commands) = state else { return }
        moveCommandSelection(by: delta, in: commands)
    }

    func onEnterPressed() {
        if case .commands(let commands) = state {
            runSelectedCommand(commands)
            return
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            SearchPopupController.shared.close(restoreFocus: true)
            return
        }

        let foreground = SearchPopupController.shared.closeForBackgroundPlayback()
        Task { @MainActor in
            await SearchPopupController.shared.waitUntilDismissed()
            SpotifyBackgroundController.shared.play(query: trimmedQuery, preserving: foreground)
        }
    }

    private func updateCommandResults(for query: String) {
        let commands = filteredCommands(matching: commandSearchText(in: query))
        selectedIndex = commands.firstIndex(where: { $0.isEnabled }) ?? 0
        state = .commands(commands)
    }

    private func moveCommandSelection(by delta: Int, in commands: [SearchCommandItem]) {
        guard !commands.isEmpty, commands.contains(where: { $0.isEnabled }) else { return }
        let count = commands.count
        var next = commands.indices.contains(selectedIndex) ? selectedIndex : 0

        for _ in 0..<count {
            next = ((next + delta) % count + count) % count
            if commands[next].isEnabled {
                selectedIndex = next
                return
            }
        }
    }

    private func filteredCommands(matching searchText: String) -> [SearchCommandItem] {
        let commands = orderCommands(buildNowPlayingCommands())
        let normalized = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return commands }

        let terms = normalized.split(separator: " ").map(String.init)
        return commands.filter { command in
            let haystack = "\(command.title) \(command.subtitle)".lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    private func buildNowPlayingCommands() -> [SearchCommandItem] {
        let playbackState = stateManager?.currentState
        let isSpotify = playbackState?.app?.bundleIdentifier == "com.spotify.client"
        let trackName = nonEmpty(playbackState?.trackName)
        let artistName = nonEmpty(playbackState?.artistName)
        let albumName = nonEmpty(playbackState?.albumName)
        let hasSpotifyTrack = isSpotify && trackName != nil
        let unavailable = "No Spotify track is available"

        return [
            SearchCommandItem(
                kind: .goToAlbum,
                title: "Go to album",
                subtitle: albumName ?? "No album is available",
                systemImage: "square.stack",
                isEnabled: isSpotify && albumName != nil && hasSpotifyTrack
            ),
            SearchCommandItem(
                kind: .goToArtist,
                title: "Go to artist",
                subtitle: artistName ?? "No artist is available",
                systemImage: "person.crop.circle",
                isEnabled: isSpotify && artistName != nil && hasSpotifyTrack
            ),
            SearchCommandItem(
                kind: .goToTrack,
                title: "Go to track",
                subtitle: trackSubtitle(trackName: trackName, artistName: artistName) ?? unavailable,
                systemImage: "music.note",
                isEnabled: hasSpotifyTrack
            ),
            SearchCommandItem(
                kind: .restartCurrentTrack,
                title: "Restart current track",
                subtitle: trackSubtitle(trackName: trackName, artistName: artistName) ?? unavailable,
                systemImage: "backward.end.fill",
                isEnabled: hasSpotifyTrack
            ),
            SearchCommandItem(
                kind: .sleepTimer5Minutes,
                title: "5 minutes",
                subtitle: "Sleep timer",
                systemImage: "timer",
                isEnabled: hasSpotifyTrack,
                sortTitle: "Sleep timer 05 minutes"
            ),
            SearchCommandItem(
                kind: .sleepTimer10Minutes,
                title: "10 minutes",
                subtitle: "Sleep timer",
                systemImage: "timer",
                isEnabled: hasSpotifyTrack,
                sortTitle: "Sleep timer 10 minutes"
            ),
            SearchCommandItem(
                kind: .sleepTimer15Minutes,
                title: "15 minutes",
                subtitle: "Sleep timer",
                systemImage: "timer",
                isEnabled: hasSpotifyTrack,
                sortTitle: "Sleep timer 15 minutes"
            ),
            SearchCommandItem(
                kind: .sleepTimer30Minutes,
                title: "30 minutes",
                subtitle: "Sleep timer",
                systemImage: "timer",
                isEnabled: hasSpotifyTrack,
                sortTitle: "Sleep timer 30 minutes"
            ),
            SearchCommandItem(
                kind: .sleepTimer45Minutes,
                title: "45 minutes",
                subtitle: "Sleep timer",
                systemImage: "timer",
                isEnabled: hasSpotifyTrack,
                sortTitle: "Sleep timer 45 minutes"
            ),
            SearchCommandItem(
                kind: .sleepTimer1Hour,
                title: "1 hour",
                subtitle: "Sleep timer",
                systemImage: "timer",
                isEnabled: hasSpotifyTrack,
                sortTitle: "Sleep timer 60 minutes"
            ),
            SearchCommandItem(
                kind: .sleepTimerEndOfTrack,
                title: "End of track",
                subtitle: "Sleep timer",
                systemImage: "timer",
                isEnabled: hasSpotifyTrack,
                sortTitle: "Sleep timer end of track"
            )
        ]
    }

    private func orderCommands(_ commands: [SearchCommandItem]) -> [SearchCommandItem] {
        let commandByKind = Dictionary(uniqueKeysWithValues: commands.map { ($0.kind, $0) })
        let used = commandUsageOrder().compactMap { commandByKind[$0] }
        let usedKinds = Set(used.map(\.kind))
        let unused = commands
            .filter { !usedKinds.contains($0.kind) }
            .sorted {
                $0.sortTitle.localizedCaseInsensitiveCompare($1.sortTitle) == .orderedAscending
            }
        return used + unused
    }

    private func commandUsageOrder() -> [SearchCommandKind] {
        let rawValues = UserDefaults.standard.stringArray(forKey: commandUsageKey) ?? []
        var seen = Set<SearchCommandKind>()
        return rawValues.compactMap { rawValue in
            guard let kind = SearchCommandKind(rawValue: rawValue), !seen.contains(kind) else {
                return nil
            }
            seen.insert(kind)
            return kind
        }
    }

    private func recordCommandUse(_ kind: SearchCommandKind) {
        var order = commandUsageOrder()
        order.removeAll { $0 == kind }
        order.insert(kind, at: 0)
        UserDefaults.standard.set(order.map(\.rawValue), forKey: commandUsageKey)
    }

    private func runSelectedCommand(_ commands: [SearchCommandItem]) {
        guard commands.indices.contains(selectedIndex) else { return }
        let command = commands[selectedIndex]
        guard command.isEnabled else { return }
        runCommand(command.kind)
    }

    private func runCommand(_ kind: SearchCommandKind) {
        switch kind {
        case .restartCurrentTrack:
            guard let app = currentSpotifyApp() else { return }
            guard AppleScriptHelper.setPlaybackPosition(0, for: app) else { return }
            recordCommandUse(kind)
            showToast("Restarted current track", closeAfterToast: true)

        case .sleepTimer5Minutes:
            setSleepTimer(after: 5 * 60, label: "5 minutes", command: kind)

        case .sleepTimer10Minutes:
            setSleepTimer(after: 10 * 60, label: "10 minutes", command: kind)

        case .sleepTimer15Minutes:
            setSleepTimer(after: 15 * 60, label: "15 minutes", command: kind)

        case .sleepTimer30Minutes:
            setSleepTimer(after: 30 * 60, label: "30 minutes", command: kind)

        case .sleepTimer45Minutes:
            setSleepTimer(after: 45 * 60, label: "45 minutes", command: kind)

        case .sleepTimer1Hour:
            setSleepTimer(after: 60 * 60, label: "1 hour", command: kind)

        case .sleepTimerEndOfTrack:
            setSleepTimerAtEndOfTrack(command: kind)

        case .goToTrack:
            guard let state = stateManager?.currentState, isSpotify(state), state.trackName != nil else { return }
            guard let uri = state.spotifyTrackURI ?? AppleScriptHelper.currentSpotifyTrackURI() else { return }
            recordCommandUse(kind)
            AppleScriptHelper.openSpotifyURI(uri)
            SearchPopupController.shared.close(restoreFocus: false)

        case .goToAlbum:
            guard let state = stateManager?.currentState,
                  isSpotify(state), let album = nonEmpty(state.albumName) else { return }
            recordCommandUse(kind)
            AppleScriptHelper.openSpotifyURI(
                AppleScriptHelper.spotifyAlbumSearchURI(album: album, artist: state.artistName)
            )
            SearchPopupController.shared.close(restoreFocus: false)

        case .goToArtist:
            guard let state = stateManager?.currentState,
                  isSpotify(state), let artist = nonEmpty(state.artistName) else { return }
            recordCommandUse(kind)
            AppleScriptHelper.openSpotifyURI(AppleScriptHelper.spotifyArtistSearchURI(artist: artist))
            SearchPopupController.shared.close(restoreFocus: false)
        }
    }

    private func setSleepTimer(after seconds: TimeInterval, label: String, command: SearchCommandKind) {
        guard let app = currentSpotifyApp() else { return }
        scheduleSleepTimer(after: seconds, app: app)
        recordCommandUse(command)
        showToast("Sleep timer set: \(label)", closeAfterToast: true)
    }

    private func setSleepTimerAtEndOfTrack(command: SearchCommandKind) {
        guard let app = currentSpotifyApp(),
              let duration = AppleScriptHelper.getTrackDuration(from: app),
              let position = AppleScriptHelper.getPlaybackPosition(from: app) else { return }
        let remaining = max(duration - position, 0)
        scheduleSleepTimer(after: remaining, app: app)
        recordCommandUse(command)
        showToast("Sleep timer set: end of track", closeAfterToast: true)
    }

    private func scheduleSleepTimer(after seconds: TimeInterval, app: MediaApp) {
        sleepTimerTask?.cancel()
        let bufferedSeconds = max(seconds - 1, 0)
        sleepTimerTask = Task { [weak self] in
            let nanoseconds = UInt64(bufferedSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            if Task.isCancelled { return }
            await MainActor.run {
                _ = AppleScriptHelper.sendCommand(.pause, to: app)
                self?.sleepTimerTask = nil
            }
        }
    }

    private func currentSpotifyApp() -> MediaApp? {
        guard let state = stateManager?.currentState,
              isSpotify(state),
              state.trackName != nil else {
            return nil
        }
        return state.app
    }

    private func trackSubtitle(trackName: String?, artistName: String?) -> String? {
        guard let trackName else { return nil }
        guard let artistName else { return trackName }
        return "\(trackName) by \(artistName)"
    }

    private func isSpotify(_ state: PlaybackState) -> Bool {
        state.app?.bundleIdentifier == "com.spotify.client"
    }

    private func isCommandQuery(_ value: String) -> Bool {
        value.hasPrefix(commandPrefix)
    }

    private func commandSearchText(in value: String) -> String {
        guard value.hasPrefix(commandPrefix) else { return "" }
        return String(value.dropFirst(commandPrefix.count))
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

}
