import Foundation

enum SpotifyUserAPIError: Error {
    case notSignedIn
    case keychain(String)
    case invalidURI(String)
    case tokenExchangeFailed(String)
    case tokenRefreshFailed(String)
    case noActiveDevice
    case premiumRequired
    case rateLimited
    case network
    case httpStatus(Int, String)
}

struct SpotifyQueueItem: Equatable {
    let id: String
    let title: String
    let artistName: String
    let albumName: String?
    let artworkURL: URL?
}

struct SpotifyDevice: Decodable {
    let id: String?
    let is_active: Bool
    let name: String
    let type: String
}

enum SpotifyRepeatMode: String {
    case track
    case context
    case off
}

struct SpotifyTrackContext {
    let albumURI: String
    let artistURI: String?
    let artistName: String?
}

struct SpotifyPlaybackSnapshot {
    let shuffleState: Bool
}

/// User-scoped Web API client. Uses a token from SpotifyAuthManager and
/// refreshes transparently on 401.
struct SpotifyUserAPI {
    static let shared = SpotifyUserAPI()

    private let session: URLSession = .shared

    /// Play a Spotify context. If `trackURI` is supplied, playback starts at
    /// that track within the context. This
    ///   is what native Spotify does when you click a song — the rest of the
    ///   album queues up, then autoplay takes over.
    func play(contextURI: String, trackURI: String? = nil, deviceID: String? = nil) async throws {
        var components = URLComponents(string: "https://api.spotify.com/v1/me/player/play")!
        if let deviceID {
            components.queryItems = [URLQueryItem(name: "device_id", value: deviceID)]
        }
        var body: [String: Any] = ["context_uri": contextURI]
        if let trackURI {
            body["offset"] = ["uri": trackURI]
        }
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await sendJSON(url: components.url!, method: "PUT", body: payload)
    }

    func albumContextURI(forTrackURI trackURI: String) async throws -> String {
        try await trackContext(forTrackURI: trackURI).albumURI
    }

    func trackContext(forTrackURI trackURI: String) async throws -> SpotifyTrackContext {
        guard let id = spotifyID(from: trackURI, expectedType: "track") else {
            throw SpotifyUserAPIError.invalidURI(trackURI)
        }
        let url = URL(string: "https://api.spotify.com/v1/tracks/\(id)")!
        let data = try await sendJSON(url: url, method: "GET", body: nil)
        struct Track: Decodable {
            struct Album: Decodable { let uri: String }
            struct Artist: Decodable {
                let name: String
                let uri: String?
            }
            let album: Album
            let artists: [Artist]
        }
        let track = try JSONDecoder().decode(Track.self, from: data)
        let artistName = track.artists
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return SpotifyTrackContext(
            albumURI: track.album.uri,
            artistURI: track.artists.first?.uri,
            artistName: artistName.isEmpty ? nil : artistName
        )
    }

    func queueTrack(uri: String, deviceID: String? = nil) async throws {
        var components = URLComponents(string: "https://api.spotify.com/v1/me/player/queue")!
        var items = [URLQueryItem(name: "uri", value: uri)]
        if let deviceID {
            items.append(URLQueryItem(name: "device_id", value: deviceID))
        }
        components.queryItems = items
        _ = try await sendJSON(url: components.url!, method: "POST", body: nil)
    }

    func setRepeatMode(_ repeatMode: SpotifyRepeatMode, deviceID: String? = nil) async throws {
        var components = URLComponents(string: "https://api.spotify.com/v1/me/player/repeat")!
        var items = [URLQueryItem(name: "state", value: repeatMode.rawValue)]
        if let deviceID {
            items.append(URLQueryItem(name: "device_id", value: deviceID))
        }
        components.queryItems = items
        _ = try await sendJSON(url: components.url!, method: "PUT", body: nil)
    }

    func seek(toPositionMs positionMs: Int, deviceID: String? = nil) async throws {
        var components = URLComponents(string: "https://api.spotify.com/v1/me/player/seek")!
        var items = [URLQueryItem(name: "position_ms", value: String(max(positionMs, 0)))]
        if let deviceID {
            items.append(URLQueryItem(name: "device_id", value: deviceID))
        }
        components.queryItems = items
        _ = try await sendJSON(url: components.url!, method: "PUT", body: nil)
    }

    func setShuffle(_ enabled: Bool, deviceID: String? = nil) async throws {
        var components = URLComponents(string: "https://api.spotify.com/v1/me/player/shuffle")!
        var items = [URLQueryItem(name: "state", value: enabled ? "true" : "false")]
        if let deviceID {
            items.append(URLQueryItem(name: "device_id", value: deviceID))
        }
        components.queryItems = items
        _ = try await sendJSON(url: components.url!, method: "PUT", body: nil)
    }

    func playbackState() async throws -> SpotifyPlaybackSnapshot? {
        let url = URL(string: "https://api.spotify.com/v1/me/player")!
        let data = try await sendJSON(url: url, method: "GET", body: nil)
        guard !data.isEmpty else { return nil }

        struct PlaybackResponse: Decodable {
            let shuffleState: Bool

            enum CodingKeys: String, CodingKey {
                case shuffleState = "shuffle_state"
            }
        }

        let decoded = try JSONDecoder().decode(PlaybackResponse.self, from: data)
        return SpotifyPlaybackSnapshot(shuffleState: decoded.shuffleState)
    }

    func currentQueue(limit: Int = 5) async throws -> [SpotifyQueueItem] {
        let url = URL(string: "https://api.spotify.com/v1/me/player/queue")!
        let data = try await sendJSON(url: url, method: "GET", body: nil)
        let decoded = try JSONDecoder().decode(QueueResponse.self, from: data)
        return Array(decoded.queue.compactMap { SpotifyQueueItem($0) }.prefix(limit))
    }

    func devices() async throws -> [SpotifyDevice] {
        let url = URL(string: "https://api.spotify.com/v1/me/player/devices")!
        let data = try await sendJSON(url: url, method: "GET", body: nil)
        struct Wrapper: Decodable { let devices: [SpotifyDevice] }
        return (try? JSONDecoder().decode(Wrapper.self, from: data).devices) ?? []
    }

    func transferPlayback(to deviceID: String, play: Bool = false) async throws {
        let url = URL(string: "https://api.spotify.com/v1/me/player")!
        let payload = try JSONSerialization.data(withJSONObject: [
            "device_ids": [deviceID],
            "play": play
        ])
        _ = try await sendJSON(url: url, method: "PUT", body: payload)
    }

    // MARK: - Core

    private func sendJSON(url: URL, method: String, body: Data?) async throws -> Data {
        let token = try await SpotifyAuthManager.shared.accessToken()
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw SpotifyUserAPIError.network
        }
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyUserAPIError.network
        }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            // Token expired between our expiresAt check and the server's clock —
            // retry once with a freshly refreshed token.
            let retryToken = try await SpotifyAuthManager.shared.accessToken(forceRefresh: true)
            var retry = req
            retry.setValue("Bearer \(retryToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResp) = try await session.data(for: retry)
            guard let retryHttp = retryResp as? HTTPURLResponse, (200..<300).contains(retryHttp.statusCode) else {
                let body = String(data: retryData, encoding: .utf8) ?? ""
                throw SpotifyUserAPIError.httpStatus((retryResp as? HTTPURLResponse)?.statusCode ?? 0, body)
            }
            return retryData
        case 403:
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.lowercased().contains("premium") {
                throw SpotifyUserAPIError.premiumRequired
            }
            throw SpotifyUserAPIError.httpStatus(403, body)
        case 404:
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.lowercased().contains("no active device") || body.lowercased().contains("no_active_device") {
                throw SpotifyUserAPIError.noActiveDevice
            }
            throw SpotifyUserAPIError.httpStatus(404, body)
        case 429:
            throw SpotifyUserAPIError.rateLimited
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SpotifyUserAPIError.httpStatus(http.statusCode, body)
        }
    }

    private func spotifyID(from value: String, expectedType: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let uriPrefix = "spotify:\(expectedType):"
        if trimmed.hasPrefix(uriPrefix) {
            let id = String(trimmed.dropFirst(uriPrefix.count))
                .split(separator: "?")
                .first
                .map(String.init) ?? ""
            return id.isEmpty ? nil : id
        }
        guard
            let components = URLComponents(string: trimmed),
            components.host == "open.spotify.com"
        else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == expectedType else { return nil }
        return parts[1].isEmpty ? nil : parts[1]
    }

    fileprivate struct QueueResponse: Decodable {
        let queue: [QueueObject]
    }

    fileprivate struct QueueObject: Decodable {
        let id: String?
        let name: String
        let uri: String?
        let type: String?
        let artists: [ArtistRef]?
        let album: AlbumRef?
    }

    fileprivate struct ArtistRef: Decodable {
        let name: String
    }

    fileprivate struct AlbumRef: Decodable {
        let name: String?
        let images: [SpotifyImage]?
    }
}

private extension SpotifyQueueItem {
    init?(_ item: SpotifyUserAPI.QueueObject) {
        guard item.type == "track" else {
            return nil
        }

        let fallbackID = item.uri.flatMap { SpotifyQueueItem.spotifyID(from: $0) }
        guard let id = item.id ?? fallbackID else {
            return nil
        }

        let artistName: String
        if let artistNames = item.artists?
            .map({ $0.name.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
            .joined(separator: ", "),
           !artistNames.isEmpty {
            artistName = artistNames
        } else {
            artistName = "Unknown Artist"
        }
        self.id = "queue:\(id)"
        self.title = item.name
        self.artistName = artistName
        self.albumName = item.album?.name
        self.artworkURL = SpotifyQueueItem.smallestImageURL(item.album?.images ?? [])
    }

    private static func spotifyID(from uri: String) -> String? {
        let prefix = "spotify:track:"
        guard uri.hasPrefix(prefix) else { return nil }
        let id = String(uri.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }

    private static func smallestImageURL(_ images: [SpotifyImage]) -> URL? {
        guard !images.isEmpty else { return nil }
        let sorted = images.sorted { ($0.width ?? .max) < ($1.width ?? .max) }
        return sorted.first.flatMap { URL(string: $0.url) }
    }
}
