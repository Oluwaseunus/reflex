import Foundation
import Combine
import AppKit

enum SearchPopupState: Equatable {
    case idle
    case loading
    case results([MediaSearchResult])
    case recents([MediaSearchResult])
    case empty
    case error(SearchBannerKind)
}

enum SearchBannerKind: Equatable {
    case playerNotRunning
    case rateLimited
    case network
    case notAuthenticated
    case generic
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var selectedIndex: Int = 0
    @Published var state: SearchPopupState = .idle
    @Published var toast: String?

    private let search: MediaSearchProvider
    private let playback: MediaPlaybackProvider
    private let recents: RecentPlaysStore

    private var searchTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var isPlaybackRequestInFlight = false

    init(search: MediaSearchProvider, playback: MediaPlaybackProvider, recents: RecentPlaysStore = .shared) {
        self.search = search
        self.playback = playback
        self.recents = recents
    }

    func reset(loadRecents: Bool = true) {
        searchTask?.cancel()
        searchTask = nil
        toastTask?.cancel()
        toastTask = nil
        toast = nil
        isPlaybackRequestInFlight = false
        query = ""
        selectedIndex = 0
        state = loadRecents ? idleState() : .idle
    }

    private func showToast(_ message: String, duration: TimeInterval = 1.6) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if Task.isCancelled { return }
            await MainActor.run { self?.toast = nil }
        }
    }

    func onQueryChanged(_ newValue: String) {
        query = newValue
        searchTask?.cancel()
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            selectedIndex = 0
            state = idleState()
            return
        }
        state = .loading
        runSearch(for: trimmed)
    }

    private func idleState() -> SearchPopupState {
        let items = recents.load()
        return items.isEmpty ? .idle : .recents(items)
    }

    private func runSearch(for query: String) {
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            guard let self else { return }
            do {
                let results = try await self.search.search(query: query)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.selectedIndex = 0
                    self.state = results.isEmpty ? .empty : .results(results)
                }
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                let kind: SearchBannerKind
                switch error {
                case MediaSearchError.notAuthenticated: kind = .notAuthenticated
                case MediaSearchError.rateLimited: kind = .rateLimited
                case MediaSearchError.network: kind = .network
                default: kind = .generic
                }
                await MainActor.run { self.state = .error(kind) }
            }
        }
    }

    func moveSelection(by delta: Int) {
        let items: [MediaSearchResult]
        switch state {
        case .results(let xs), .recents(let xs): items = xs
        default: return
        }
        guard !items.isEmpty else { return }
        let count = items.count
        // Modulo that handles negative deltas so ↑ from index 0 wraps to the last item.
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    func onEnterPressed() {
        guard let item = currentItem() else { return }
        play(item: item)
    }

    func onShiftEnterPressed() {
        guard let item = currentItem() else { return }
        play(item: item)
    }

    private func play(item: MediaSearchResult) {
        guard !isPlaybackRequestInFlight else { return }
        isPlaybackRequestInFlight = true
        Task {
            do {
                try await playback.play(item: item)
                self.recents.record(item)
                await MainActor.run {
                    SearchPopupController.shared.closeAfterPlayback()
                }
            } catch MediaPlaybackError.playerNotRunning {
                await MainActor.run {
                    self.isPlaybackRequestInFlight = false
                    self.state = .error(.playerNotRunning)
                }
            } catch SpotifyUserAPIError.notSignedIn {
                await MainActor.run {
                    self.isPlaybackRequestInFlight = false
                    self.state = .error(.notAuthenticated)
                }
            } catch SpotifyUserAPIError.rateLimited {
                await MainActor.run {
                    self.isPlaybackRequestInFlight = false
                    self.state = .error(.rateLimited)
                }
            } catch SpotifyUserAPIError.network {
                await MainActor.run {
                    self.isPlaybackRequestInFlight = false
                    self.state = .error(.network)
                }
            } catch {
                await MainActor.run {
                    self.isPlaybackRequestInFlight = false
                    self.state = .error(.generic)
                }
            }
        }
    }

    /// Queue the currently-selected track. Requires sign-in; silently ignored
    /// for non-track results (Web API's queue endpoint only accepts single tracks).
    /// Unlike play, queue keeps the popup open so the user can queue multiple
    /// tracks in a row — confirmation comes via a transient toast.
    func onCommandEnterPressed() {
        guard let item = currentItem(), item.type == .track else { return }
        let provider = playback as? SpotifyPlaybackProvider
        guard let provider else { return }
        Task {
            do {
                try await provider.queue(uri: item.playbackURI)
                await MainActor.run {
                    self.showToast("Added \(item.title) to queue")
                }
            } catch MediaPlaybackError.playerNotRunning {
                await MainActor.run { self.state = .error(.playerNotRunning) }
            } catch SpotifyUserAPIError.notSignedIn {
                await MainActor.run { self.state = .error(.notAuthenticated) }
            } catch SpotifyUserAPIError.rateLimited {
                await MainActor.run { self.state = .error(.rateLimited) }
            } catch SpotifyUserAPIError.network {
                await MainActor.run { self.state = .error(.network) }
            } catch {
                await MainActor.run { self.state = .error(.generic) }
            }
        }
    }

    private func currentItem() -> MediaSearchResult? {
        let items: [MediaSearchResult]
        switch state {
        case .results(let xs), .recents(let xs): items = xs
        default: return nil
        }
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    func openSpotifyApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        }
        SearchPopupController.shared.close()
    }
}
