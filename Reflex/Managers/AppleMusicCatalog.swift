import Foundation
import MusicKit

extension Notification.Name {
    static let musicAuthorizationChanged = Notification.Name("com.reflex.musicAuthorizationChanged")
}

struct CatalogMusicItem: Equatable {
    let id: String
    let name: String
    let url: URL?
}

/// Catalog identities remain separate from the Music app's local persistent ID.
struct AppleMusicCatalogDetails: Equatable {
    let trackKey: String
    let track: CatalogMusicItem
    let albums: [CatalogMusicItem]
    let artists: [CatalogMusicItem]
    let primaryArtistURL: URL?

    func url(for destination: PlaybackNavigation.Destination) -> URL? {
        switch destination {
        case .track: return track.url
        case .album: return albums.count == 1 ? albums.first?.url : nil
        case .artist: return artists.first?.url ?? primaryArtistURL
        }
    }
}

enum AppleMusicIdentity {
    static func isValidPersistentID(_ persistentID: String?) -> Bool {
        guard let value = persistentID?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.count == 16, let number = UInt64(value, radix: 16) else { return false }
        return number != 0
    }

    static func catalogSongID(from url: URL?) -> String? {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == "music.apple.com", ["https", "musics"].contains(components.scheme) else { return nil }
        let parts = components.path.split(separator: "/")
        guard parts.count >= 3 else { return nil }
        let value: String?
        if parts[1] == "album" {
            value = components.queryItems?.first(where: { $0.name == "i" })?.value
        } else if parts[1] == "song" {
            value = parts.last.map(String.init)
        } else {
            return nil
        }
        guard let value, !value.isEmpty,
              value.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return value
    }
}

enum AppleMusicCatalogError: LocalizedError {
    case needsAuthorization, denied, identityUnavailable, ambiguousMatch, unavailableLink

    var errorDescription: String? {
        switch self {
        case .needsAuthorization:
            return "Connect Apple Music in Reflex Settings → Permissions, then try again."
        case .denied:
            return "Allow Reflex access to Apple Music in System Settings → Privacy & Security → Media & Apple Music."
        case .identityUnavailable:
            return "No Apple Music catalog song matched the current track’s title, artist, album, and duration."
        case .ambiguousMatch:
            return "More than one Apple Music recording matches this track. Reflex couldn’t determine which version to open."
        case .unavailableLink:
            return "Apple Music doesn’t provide a link for this item."
        }
    }
}

actor AppleMusicCatalogResolver {
    static let shared = AppleMusicCatalogResolver()
    private var cache: [String: AppleMusicCatalogDetails] = [:]
    private var pending: [String: Task<AppleMusicCatalogDetails, Error>] = [:]
    private let load: (PlaybackState) async throws -> AppleMusicCatalogDetails

    init(load: @escaping (PlaybackState) async throws -> AppleMusicCatalogDetails = AppleMusicCatalogResolver.loadCatalogDetails) {
        self.load = load
    }

    func details(for state: PlaybackState) async throws -> AppleMusicCatalogDetails {
        if let cached = cache[state.trackKey] { return cached }
        if let task = pending[state.trackKey] {
            let details = try await task.value
            try Task.checkCancellation()
            return details
        }
        let task = Task { try await load(state) }
        pending[state.trackKey] = task
        defer { pending[state.trackKey] = nil }
        let details = try await task.value
        if cache.count >= 128 { cache.removeAll() }
        cache[state.trackKey] = details
        try Task.checkCancellation()
        return details
    }

    static func loadCatalogDetails(for state: PlaybackState) async throws -> AppleMusicCatalogDetails {
        switch MusicAuthorization.currentStatus {
        case .authorized: break
        case .notDetermined: throw AppleMusicCatalogError.needsAuthorization
        default: throw AppleMusicCatalogError.denied
        }
        let country = try await MusicDataRequest.currentCountryCode
        let directID = await AppleScriptHelper.currentAppleMusicCatalogSongID(expectedPersistentID: state.trackIdentifier)
        return try await AppleMusicCatalogRequest.resolve(state: state, country: country, directID: directID) {
            try await MusicDataRequest(urlRequest: $0).response().data
        }
    }
}

enum AppleMusicCatalogRequest {
    static func resolve(state: PlaybackState, country: String, directID: String? = nil,
                        send: (URLRequest) async throws -> Data) async throws -> AppleMusicCatalogDetails {
        let request = try request(state: state, country: country, directID: directID)
        Logger.shared.info("Apple Music catalog request path=\(request.url?.path ?? "") includes=albums,artists")
        let data = try await send(request)
        let response = try JSONDecoder().decode(AppleMusicCatalogResponse.self, from: data)
        let songs = directID == nil ? response.results?.songs?.data ?? [] : response.data ?? []
        let song: AppleMusicCatalogSong
        if let directID {
            guard let found = songs.first(where: { $0.id == directID }) else {
                throw AppleMusicCatalogError.identityUnavailable
            }
            song = found
        } else {
            let candidates = songs.map {
                AppleMusicCatalogCandidate(id: $0.id, title: $0.attributes.name, artist: $0.attributes.artistName,
                                           album: $0.attributes.albumName,
                                           duration: $0.attributes.durationInMillis.map { $0 / 1000 }, isrc: $0.attributes.isrc)
            }
            guard let id = try AppleMusicCatalogMatch.songID(for: state, candidates: candidates),
                  let found = songs.first(where: { $0.id == id }) else {
                throw AppleMusicCatalogError.identityUnavailable
            }
            song = found
        }
        let details = song.details(trackKey: state.trackKey)
        Logger.shared.info("Apple Music catalog response track=\(details.track.id) albums=\(details.albums.count) artists=\(details.artists.count) artistURLs=\(details.artists.compactMap(\.url).count)")
        return details
    }

    static func request(state: PlaybackState, country: String, directID: String? = nil) throws -> URLRequest {
        guard country.utf8.count == 2, country.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }) else {
            throw AppleMusicCatalogError.identityUnavailable
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.music.apple.com"
        if let directID {
            guard !directID.isEmpty, directID.utf8.allSatisfy({ (48...57).contains($0) }) else {
                throw AppleMusicCatalogError.identityUnavailable
            }
            components.path = "/v1/catalog/\(country.lowercased())/songs/\(directID)"
            components.queryItems = [URLQueryItem(name: "include", value: "albums,artists"),
                                     URLQueryItem(name: "extend", value: "artistUrl")]
        } else {
            guard let title = state.trackName, let artist = state.artistName,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppleMusicCatalogError.identityUnavailable
            }
            components.path = "/v1/catalog/\(country.lowercased())/search"
            components.queryItems = [
                URLQueryItem(name: "term", value: [title, artist, state.albumName].compactMap { $0 }.joined(separator: " ")),
                URLQueryItem(name: "types", value: "songs"),
                URLQueryItem(name: "limit", value: "25"),
                URLQueryItem(name: "include[songs]", value: "albums,artists"),
                URLQueryItem(name: "extend[songs]", value: "artistUrl")
            ]
        }
        guard let url = components.url else { throw AppleMusicCatalogError.identityUnavailable }
        return URLRequest(url: url)
    }
}

private struct AppleMusicCatalogResponse: Decodable {
    let results: Results?
    let data: [AppleMusicCatalogSong]?
    struct Results: Decodable {
        let songs: Songs?
    }
    struct Songs: Decodable {
        let data: [AppleMusicCatalogSong]
    }
}

private struct AppleMusicCatalogSong: Decodable {
    let id: String
    let attributes: Attributes
    let relationships: Relationships?

    struct Attributes: Decodable {
        let name: String
        let artistName: String
        let albumName: String?
        let durationInMillis: Double?
        let isrc: String?
        let url: URL?
        let artistUrl: URL?
    }
    struct Relationships: Decodable {
        let albums: RelatedItems?
        let artists: RelatedItems?
    }
    struct RelatedItems: Decodable {
        let data: [RelatedItem]
    }
    struct RelatedItem: Decodable {
        let id: String
        let attributes: Attributes?
        struct Attributes: Decodable {
            let name: String
            let url: URL?
        }
        var item: CatalogMusicItem {
            CatalogMusicItem(id: id, name: attributes?.name ?? "", url: attributes?.url)
        }
    }

    func details(trackKey: String) -> AppleMusicCatalogDetails {
        AppleMusicCatalogDetails(trackKey: trackKey,
            track: CatalogMusicItem(id: id, name: attributes.name, url: attributes.url),
            albums: relationships?.albums?.data.map(\.item) ?? [],
            artists: relationships?.artists?.data.map(\.item) ?? [],
            primaryArtistURL: attributes.artistUrl)
    }
}

struct AppleMusicCatalogCandidate {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let duration: TimeInterval?
    let isrc: String?
}

enum AppleMusicCatalogMatch {
    static func songID(for state: PlaybackState, candidates: [AppleMusicCatalogCandidate]) throws -> String? {
        guard let title = state.trackName, let artist = state.artistName,
              !normalized(title).isEmpty, !normalized(artist).isEmpty else { return nil }
        let matches = candidates.filter { candidate in
            guard candidate.id.utf8.allSatisfy({ (48...57).contains($0) }), !candidate.id.isEmpty,
                  normalized(candidate.title) == normalized(title),
                  artists(candidate.artist) == artists(artist) else { return false }
            if let album = state.albumName, !normalized(album).isEmpty,
               normalized(candidate.album ?? "") != normalized(album) { return false }
            if let duration = state.duration, duration > 0 {
                guard let candidateDuration = candidate.duration,
                      abs(candidateDuration - duration) <= 2 else { return false }
            }
            return true
        }
        let ids = Set(matches.map(\.id))
        if ids.count <= 1 { return matches.first?.id }
        // Duplicate catalog releases can reference the same recorded performance.
        let isrcs = Set(matches.compactMap(\.isrc).filter { !$0.isEmpty })
        guard isrcs.count == 1, matches.allSatisfy({ $0.isrc?.isEmpty == false }) else {
            throw AppleMusicCatalogError.ambiguousMatch
        }
        return matches.first?.id
    }

    private static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func artists(_ value: String) -> [String] {
        normalized(value).components(separatedBy: CharacterSet(charactersIn: ",&;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.sorted()
    }
}

enum AppleMusicDeepLink {
    static func url(from url: URL, destination: PlaybackNavigation.Destination) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host == "music.apple.com" else { return nil }
        components.scheme = "musics"
        components.queryItems = destination == .track
            ? components.queryItems?.filter { $0.name == "i" } : nil
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        components.fragment = nil
        return components.url
    }
}
