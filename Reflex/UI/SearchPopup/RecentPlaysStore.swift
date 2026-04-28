import Foundation

/// Persists the last 5 played tracks/albums to UserDefaults so the search
/// popup can show recents before the user types anything.
final class RecentPlaysStore {
    static let shared = RecentPlaysStore()

    private let key = "spotifySearch.recentPlays"
    private let limit = 5

    private init() {}

    func load() -> [MediaSearchResult] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([LossyRecentPlayRecord].self, from: data) else {
            return []
        }
        return records.compactMap { $0.value?.searchResult }
    }

    func record(_ item: MediaSearchResult) {
        var current = load()
        current.removeAll { $0.id == item.id }
        current.insert(item, at: 0)
        if current.count > limit { current = Array(current.prefix(limit)) }
        let records = current.map(RecentPlayRecord.init(item:))
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private struct LossyRecentPlayRecord: Decodable {
        let value: RecentPlayRecord?

        init(from decoder: Decoder) throws {
            value = try? RecentPlayRecord(from: decoder)
        }
    }

    private struct RecentPlayRecord: Codable {
        let id: String
        let title: String?
        let subtitle: String?
        let type: MediaItemType?
        let artworkURL: URL?
        let playbackURI: String
        let contextURI: String?
        let artistName: String?
        let albumName: String?

        init(item: MediaSearchResult) {
            id = item.id
            title = item.title
            subtitle = item.subtitle
            type = item.type
            artworkURL = item.artworkURL
            playbackURI = item.playbackURI
            contextURI = item.contextURI
            artistName = item.artistName
            albumName = item.albumName
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            playbackURI = try container.decode(String.self, forKey: .playbackURI)
            title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? nil
            subtitle = (try? container.decodeIfPresent(String.self, forKey: .subtitle)) ?? nil
            type = (try? container.decodeIfPresent(MediaItemType.self, forKey: .type)) ?? nil
            artworkURL = (try? container.decodeIfPresent(URL.self, forKey: .artworkURL)) ?? nil
            contextURI = (try? container.decodeIfPresent(String.self, forKey: .contextURI)) ?? nil
            artistName = (try? container.decodeIfPresent(String.self, forKey: .artistName)) ?? nil
            albumName = (try? container.decodeIfPresent(String.self, forKey: .albumName)) ?? nil
        }

        var searchResult: MediaSearchResult? {
            guard !id.isEmpty, !playbackURI.isEmpty else { return nil }
            return MediaSearchResult(
                id: id,
                title: title ?? "Unknown",
                subtitle: subtitle ?? "",
                type: type ?? .track,
                artworkURL: artworkURL,
                playbackURI: playbackURI,
                contextURI: contextURI,
                artistName: artistName,
                albumName: albumName
            )
        }
    }
}
