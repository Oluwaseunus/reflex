import Foundation

/// Uses the signed-in user's access token (via SpotifyAuthManager). There's no
/// app-level Client Credentials flow anymore, which means search requires the
/// user to have connected their Spotify account — but also means we don't
/// ship a client secret inside the binary.
final class SpotifySearchProvider: MediaSearchProvider {
    private let session: URLSession = .shared

    var isReady: Bool { true }

    func search(query: String) async throws -> [MediaSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var token: String
        do {
            token = try await SpotifyAuthManager.shared.accessToken()
        } catch {
            throw Self.mapAuthError(error)
        }

        let (data, status) = try await performSearch(query: trimmed, token: token)

        if status == 401 {
            do {
                token = try await SpotifyAuthManager.shared.accessToken(forceRefresh: true)
            } catch {
                throw Self.mapAuthError(error)
            }
            let (retryData, retryStatus) = try await performSearch(query: trimmed, token: token)
            if retryStatus == 429 { throw MediaSearchError.rateLimited }
            guard (200..<300).contains(retryStatus) else { throw MediaSearchError.unknown }
            return try decode(data: retryData)
        }
        if status == 429 { throw MediaSearchError.rateLimited }
        guard (200..<300).contains(status) else { throw MediaSearchError.unknown }
        return try decode(data: data)
    }

    /// Only `notSignedIn` (no tokens in keychain) means "user needs to
    /// connect." Transient refresh/network failures shouldn't be surfaced as
    /// a sign-in prompt — that misleads the user into reconnecting when their
    /// account is fine.
    private static func mapAuthError(_ error: Error) -> MediaSearchError {
        switch error {
        case SpotifyUserAPIError.notSignedIn: return .notAuthenticated
        case SpotifyUserAPIError.network: return .network
        default: return .unknown
        }
    }

    private func performSearch(query: String, token: String) async throws -> (Data, Int) {
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track,album"),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components.url else { throw MediaSearchError.unknown }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            return (data, status)
        } catch {
            // Let task cancellation propagate as-is so the view model can
            // distinguish it from real network failures (avoids flashing a
            // network-error banner between keystrokes while debouncing).
            if error is CancellationError { throw error }
            if let urlErr = error as? URLError, urlErr.code == .cancelled {
                throw CancellationError()
            }
            throw MediaSearchError.network
        }
    }

    private func decode(data: Data) throws -> [MediaSearchResult] {
        do {
            let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
            let tracks = (decoded.tracks?.items ?? []).prefix(3).map { item in
                let primaryArtistRef = item.artists.first
                let primaryArtist = primaryArtistRef?.name ?? ""
                let subtitle = "\(primaryArtist) • \(item.album.name)"
                return MediaSearchResult(
                    id: "track:\(item.id)",
                    title: item.name,
                    subtitle: subtitle,
                    type: .track,
                    artworkURL: smallestImageURL(item.album.images),
                    playbackURI: item.uri,
                    contextURI: item.album.uri,
                    artistName: primaryArtist.isEmpty ? nil : primaryArtist,
                    artistURI: primaryArtistRef?.uri,
                    albumName: item.album.name
                )
            }
            let albums = (decoded.albums?.items ?? []).prefix(2).map { item in
                let primaryArtistRef = item.artists.first
                let primaryArtist = primaryArtistRef?.name ?? ""
                return MediaSearchResult(
                    id: "album:\(item.id)",
                    title: item.name,
                    subtitle: primaryArtist,
                    type: .album,
                    artworkURL: smallestImageURL(item.images),
                    playbackURI: item.uri,
                    contextURI: nil,
                    artistName: primaryArtist.isEmpty ? nil : primaryArtist,
                    artistURI: primaryArtistRef?.uri,
                    albumName: nil
                )
            }
            return Array(tracks) + Array(albums)
        } catch {
            throw MediaSearchError.unknown
        }
    }

    private func smallestImageURL(_ images: [SpotifyImage]) -> URL? {
        guard !images.isEmpty else { return nil }
        let sorted = images.sorted { ($0.width ?? .max) < ($1.width ?? .max) }
        return sorted.first.flatMap { URL(string: $0.url) }
    }

    // MARK: - Decoding models

    private struct SearchResponse: Decodable {
        let tracks: Paged<TrackItem>?
        let albums: Paged<AlbumItem>?
    }
    private struct Paged<T: Decodable>: Decodable {
        let items: [T]
    }
    private struct TrackItem: Decodable {
        let id: String
        let name: String
        let uri: String
        let artists: [ArtistRef]
        let album: AlbumRef
    }
    private struct AlbumItem: Decodable {
        let id: String
        let name: String
        let uri: String
        let artists: [ArtistRef]
        let images: [SpotifyImage]
    }
    private struct AlbumRef: Decodable {
        let uri: String
        let name: String
        let images: [SpotifyImage]
    }
    private struct ArtistRef: Decodable {
        let name: String
        let uri: String?
    }
}

struct SpotifyImage: Decodable {
    let url: String
    let width: Int?
    let height: Int?
}
