import Foundation

enum SpotifyUserAPIError: Error {
    case notSignedIn
    case tokenExchangeFailed(String)
    case tokenRefreshFailed(String)
    case noActiveDevice
    case premiumRequired
    case rateLimited
    case network
    case httpStatus(Int, String)
}

struct SpotifyDevice: Decodable {
    let id: String?
    let is_active: Bool
    let name: String
    let type: String
}

/// User-scoped Web API client. Uses a token from SpotifyAuthManager and
/// refreshes transparently on 401.
struct SpotifyUserAPI {
    static let shared = SpotifyUserAPI()

    private let session: URLSession = .shared

    /// Three call shapes:
    /// - `contextURI` only: play that album/playlist/artist from the start.
    /// - `contextURI` + `trackURI`: play context, starting at that track. This
    ///   is what native Spotify does when you click a song — the rest of the
    ///   album queues up, then autoplay takes over.
    /// - `trackURI` only: play exactly that track, no context. Playback stops
    ///   when the track ends (no autoplay, no queue).
    func play(contextURI: String? = nil, trackURI: String? = nil, deviceID: String? = nil) async throws {
        var components = URLComponents(string: "https://api.spotify.com/v1/me/player/play")!
        if let deviceID {
            components.queryItems = [URLQueryItem(name: "device_id", value: deviceID)]
        }
        var body: [String: Any] = [:]
        if let contextURI, let trackURI {
            body["context_uri"] = contextURI
            body["offset"] = ["uri": trackURI]
        } else if let contextURI {
            body["context_uri"] = contextURI
        } else if let trackURI {
            body["uris"] = [trackURI]
        }
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await sendJSON(url: components.url!, method: "PUT", body: payload)
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

}
