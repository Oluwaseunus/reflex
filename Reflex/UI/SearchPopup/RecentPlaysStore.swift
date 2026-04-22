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
              let items = try? JSONDecoder().decode([MediaSearchResult].self, from: data) else {
            return []
        }
        return items
    }

    func record(_ item: MediaSearchResult) {
        var current = load()
        current.removeAll { $0.id == item.id }
        current.insert(item, at: 0)
        if current.count > limit { current = Array(current.prefix(limit)) }
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
