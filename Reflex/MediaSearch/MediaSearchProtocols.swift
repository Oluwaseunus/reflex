import Foundation

enum MediaItemType: String, Codable {
    case track
    case album
}

struct MediaSearchResult: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let subtitle: String
    let type: MediaItemType
    let artworkURL: URL?
    let playbackURI: String
    /// Optional container URI (e.g. the track's album) used as `context_uri`
    /// when playing via the Web API. Gives native "click a track in an album"
    /// behavior — plays this item then continues through the container.
    let contextURI: String?
}

enum MediaSearchError: Error, Equatable {
    case notAuthenticated
    case network
    case rateLimited
    case unknown
}

enum MediaPlaybackError: Error {
    case playerNotRunning
    case `internal`(underlying: Error)
}

protocol MediaSearchProvider {
    var isReady: Bool { get }
    func search(query: String) async throws -> [MediaSearchResult]
}

protocol MediaPlaybackProvider {
    func play(item: MediaSearchResult) async throws
}
