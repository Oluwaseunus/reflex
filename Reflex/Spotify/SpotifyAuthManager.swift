import Foundation
import AppKit
import CryptoKit
import Combine

/// Drives the Authorization Code + PKCE flow for user-scoped Spotify Web API
/// access. Tokens persist in the keychain; refresh happens on demand.
@MainActor
final class SpotifyAuthManager: ObservableObject {
    static let shared = SpotifyAuthManager()

    @Published private(set) var isSignedIn: Bool = false

    private var pendingVerifier: String?
    private var pendingState: String?
    private var pendingRedirectURI: String?
    private var callbackServer: LoopbackCallbackServer?
    private var refreshTask: Task<String, Error>?
    private var exchangeTask: Task<Void, Never>?
    /// Bumped on sign-out. Any in-flight exchange/refresh captures the value
    /// at start and must re-check before writing tokens — otherwise a refresh
    /// that completes after Disconnect would resurrect the signed-in state.
    private var authGeneration: Int = 0
    private let session: URLSession = .shared
    private let logger = Logger.shared

    private init() {
        isSignedIn = SpotifyKeychain.load() != nil
    }

    // MARK: - Sign in

    /// True when the build was shipped with a Spotify client ID — sign-in
    /// requires one, so the UI gates its Connect button on this.
    var isConfigured: Bool { !Constants.Spotify.clientID.isEmpty }

    func beginSignIn() {
        guard isConfigured else {
            logger.error("Spotify sign-in attempted but SPOTIFY_CLIENT_ID is empty — check build env.")
            return
        }
        // Starting a new sign-in is a clean boundary: bump the generation and
        // cancel any in-flight exchange/refresh from a prior attempt so their
        // late completions can't mutate the new flow's state.
        authGeneration &+= 1
        exchangeTask?.cancel()
        exchangeTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        // If a previous sign-in was abandoned with the listener still bound,
        // tear it down so the new flow can claim a port.
        callbackServer?.stop()

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomState()

        let server = LoopbackCallbackServer()
        self.callbackServer = server
        let maybePort = server.start(
            preferredPorts: Constants.Spotify.loopbackPorts,
            expectedState: state,
            timeout: 300,
            completion: { [weak self, weak server] result in
                guard let self else { return }
                let callbackServer = server
                Task { @MainActor in
                    self.handleListenerResult(result, from: callbackServer)
                }
            }
        )
        guard let port = maybePort else {
            logger.error("Spotify auth: could not bind any loopback port from \(Constants.Spotify.loopbackPorts)")
            callbackServer = nil
            return
        }

        let redirectURI = Constants.Spotify.redirectURI(forPort: port)
        pendingVerifier = verifier
        pendingState = state
        pendingRedirectURI = redirectURI

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Constants.Spotify.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: Constants.Spotify.userScopes)
        ]
        guard let url = components.url else {
            resetPending()
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func handleListenerResult(_ result: Result<URL, LoopbackCallbackServer.CallbackError>, from server: LoopbackCallbackServer?) {
        // Drop results from a superseded listener — `beginSignIn` may have
        // already rotated `callbackServer` to a fresh instance.
        guard let server, server === callbackServer else { return }
        callbackServer = nil
        switch result {
        case .failure(let error):
            logger.error("Spotify auth: loopback listener failed — \(error)")
            resetPending()
        case .success(let url):
            handleCallbackURL(url)
        }
    }

    private func handleCallbackURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems
        else {
            resetPending()
            return
        }

        let code = items.first(where: { $0.name == "code" })?.value
        let state = items.first(where: { $0.name == "state" })?.value
        let error = items.first(where: { $0.name == "error" })?.value

        if let error {
            logger.error("Spotify auth error: \(error)")
            resetPending()
            return
        }
        guard let code,
              let state,
              state == pendingState,
              let verifier = pendingVerifier,
              let redirectURI = pendingRedirectURI
        else {
            logger.error("Spotify auth: callback missing code or state mismatch")
            resetPending()
            return
        }
        resetPending()

        exchangeTask?.cancel()
        let generation = authGeneration
        exchangeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.exchangeCode(code, verifier: verifier, redirectURI: redirectURI, generation: generation)
            } catch {
                self.logger.error("Spotify auth: token exchange failed", error: error)
            }
        }
    }

    private func resetPending() {
        pendingVerifier = nil
        pendingState = nil
        pendingRedirectURI = nil
    }

    func signOut() {
        clearAuthState(cancelRefresh: true)
    }

    private func clearAuthState(cancelRefresh: Bool) {
        authGeneration &+= 1
        callbackServer?.stop()
        callbackServer = nil
        resetPending()
        exchangeTask?.cancel()
        exchangeTask = nil
        if cancelRefresh {
            refreshTask?.cancel()
            refreshTask = nil
        }
        SpotifyKeychain.clear()
        isSignedIn = false
    }

    // MARK: - Access token for callers

    /// Returns a valid access token, refreshing if needed. Throws if the user
    /// is not signed in or the refresh call fails. Pass `forceRefresh: true`
    /// after a 401 to re-fetch even if our clock thinks the cached token is
    /// still valid.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let bundle = SpotifyKeychain.load() else {
            throw SpotifyUserAPIError.notSignedIn
        }
        if !forceRefresh, bundle.expiresAt.timeIntervalSinceNow > 60 {
            return bundle.accessToken
        }
        if let refreshTask {
            return try await refreshTask.value
        }
        let generation = authGeneration
        let task = Task<String, Error> { [weak self] in
            guard let self else { throw SpotifyUserAPIError.notSignedIn }
            return try await self.performRefresh(bundle.refreshToken, generation: generation)
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    // MARK: - Network

    private func exchangeCode(_ code: String, verifier: String, redirectURI: String, generation: Int) async throws {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": Constants.Spotify.clientID,
            "code_verifier": verifier
        ]
        req.httpBody = Self.formEncode(body).data(using: .utf8)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw SpotifyUserAPIError.tokenExchangeFailed(bodyText)
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refresh = decoded.refresh_token else {
            throw SpotifyUserAPIError.tokenExchangeFailed("missing refresh_token")
        }
        let bundle = SpotifyTokenBundle(
            accessToken: decoded.access_token,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expires_in)),
            scope: decoded.scope ?? Constants.Spotify.userScopes
        )
        // Sign-out raced us — discard. Without this, an exchange that started
        // before Disconnect would resurrect the signed-in state.
        if Task.isCancelled || generation != authGeneration { return }
        SpotifyKeychain.save(bundle)
        isSignedIn = true
    }

    /// Refresh the access token per
    /// https://developer.spotify.com/documentation/web-api/tutorials/refreshing-tokens
    ///
    /// Error handling follows OAuth 2.0 (RFC 6749 §5.2): only sign the user
    /// out when Spotify returns `invalid_grant`, which means the refresh token
    /// has been revoked or is no longer valid. Network/5xx/other failures are
    /// transient — we surface them but keep the tokens so the next call can
    /// try again.
    private func performRefresh(_ refreshToken: String, generation: Int) async throws -> String {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Constants.Spotify.clientID
        ]
        req.httpBody = Self.formEncode(body).data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            // Transient network failure — keep tokens, bubble up.
            logger.error("Spotify auth: refresh network error", error: error)
            throw SpotifyUserAPIError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw SpotifyUserAPIError.network
        }

        if (200..<300).contains(http.statusCode) {
            let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
            let bundle = SpotifyTokenBundle(
                accessToken: decoded.access_token,
                // Spec: a new refresh_token is not always returned. When
                // absent, keep the one we already have.
                refreshToken: decoded.refresh_token ?? refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expires_in)),
                scope: decoded.scope ?? Constants.Spotify.userScopes
            )
            // Sign-out raced us — return the token to the caller but don't
            // resurrect persisted state for a now-ended session.
            if Task.isCancelled || generation != authGeneration {
                throw SpotifyUserAPIError.notSignedIn
            }
            SpotifyKeychain.save(bundle)
            isSignedIn = true
            return bundle.accessToken
        }

        let bodyText = String(data: data, encoding: .utf8) ?? ""
        // Only invalid_grant means the refresh token itself is dead — that's
        // the one case where re-auth is the only path forward. Everything
        // else (transient 5xx, misconfigured client, etc) leaves tokens alone.
        if http.statusCode == 400, Self.oauthErrorCode(in: data) == "invalid_grant" {
            // A stale refresh that resumes after signOut/beginSignIn must not
            // clobber the newer session — only the current generation owns
            // the right to tear down auth state.
            if Task.isCancelled || generation != authGeneration {
                throw SpotifyUserAPIError.tokenRefreshFailed(bodyText)
            }
            logger.error("Spotify auth: refresh token invalid_grant — signing out")
            clearAuthState(cancelRefresh: false)
            throw SpotifyUserAPIError.tokenRefreshFailed(bodyText)
        }
        logger.error("Spotify auth: refresh failed (\(http.statusCode)) — \(bodyText)")
        throw SpotifyUserAPIError.tokenRefreshFailed(bodyText)
    }

    private static func oauthErrorCode(in data: Data) -> String? {
        struct OAuthError: Decodable { let error: String? }
        return (try? JSONDecoder().decode(OAuthError.self, from: data))?.error
    }

    // MARK: - PKCE helpers

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    private static func randomState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// `.urlQueryAllowed` leaves `+`, `&`, `=` and space unescaped — all of
    /// which are significant in an `application/x-www-form-urlencoded` body.
    /// Restrict to unreserved characters so a token/code containing one of
    /// them isn't misparsed by the server.
    private static let formAllowed: CharacterSet = {
        var cs = CharacterSet.alphanumerics
        cs.insert(charactersIn: "-._~")
        return cs
    }()

    private static func formEncode(_ dict: [String: String]) -> String {
        dict.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
        let scope: String?
        let token_type: String?
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
