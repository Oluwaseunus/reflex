import Foundation

/// Validates canonical Spotify identities extracted from Accessibility results.
enum SpotifySearchIdentity {
    static func searchQuery(from value: String) -> String? {
        let urlValue = value.hasPrefix("xpui.app.spotify.com/") ? "https://\(value)" : value
        guard let components = URLComponents(string: urlValue),
              components.host == "xpui.app.spotify.com",
              ["https", "http"].contains(components.scheme) else { return nil }
        let parts = components.percentEncodedPath.split(separator: "/")
        guard parts.count >= 2, parts[0] == "search" else { return nil }
        return String(parts[1]).removingPercentEncoding
    }

    enum SearchQueryMatchKind: Equatable {
        case title
        case artist
        case titleAndArtist
    }

    static func searchQueryMatchKind(_ query: String, title: String, artists: [String]) -> SearchQueryMatchKind? {
        let normalizedQuery = normalizedSearchText(query)
        let normalizedTitle = normalizedSearchText(title)
        let normalizedArtists = artists.map(normalizedSearchText).filter { !$0.isEmpty }
        guard !normalizedQuery.isEmpty, !normalizedTitle.isEmpty, !normalizedArtists.isEmpty else {
            return nil
        }
        if normalizedQuery == normalizedTitle { return .title }
        if normalizedArtists.contains(normalizedQuery) { return .artist }

        let combinedArtists = normalizedArtists.joined()
        for artist in Set(normalizedArtists + [combinedArtists]) {
            if normalizedQuery == normalizedTitle + artist
                || normalizedQuery == artist + normalizedTitle
                || normalizedQuery == normalizedTitle + "by" + artist {
                return .titleAndArtist
            }
        }
        return nil
    }

    static func matchesSearchQuery(_ query: String, title: String, artists: [String]) -> Bool {
        searchQueryMatchKind(query, title: title, artists: artists) != nil
    }

    static func normalizedIdentity(title: String, artists: [String]) -> String? {
        let normalizedTitle = normalizedSearchText(title)
        let normalizedArtists = Set(artists.map(normalizedSearchText).filter { !$0.isEmpty }).sorted()
        guard !normalizedTitle.isEmpty, !normalizedArtists.isEmpty else { return nil }
        return ([normalizedTitle] + normalizedArtists).joined(separator: "|")
    }

    static func hasAmbiguousCombinedMatches(_ normalizedIdentities: [String]) -> Bool {
        Set(normalizedIdentities).count > 1
    }

    static func selectedMatchIndex(
        matchKinds: [SearchQueryMatchKind], normalizedIdentities: [String]
    ) -> Int? {
        guard matchKinds.count == normalizedIdentities.count else { return nil }
        let combinedIndexes = matchKinds.indices.filter { matchKinds[$0] == .titleAndArtist }
        if !combinedIndexes.isEmpty {
            let collisionIndexes = matchKinds.indices.filter {
                matchKinds[$0] == .title || matchKinds[$0] == .titleAndArtist
            }
            let identities = collisionIndexes.map { normalizedIdentities[$0] }
            guard !hasAmbiguousCombinedMatches(identities) else { return nil }
            return combinedIndexes.first
        }
        return matchKinds.indices.first {
            matchKinds[$0] == .title || matchKinds[$0] == .artist
        }
    }

    private static func normalizedSearchText(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let alphanumericScalars = folded.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        return String(String.UnicodeScalarView(alphanumericScalars))
    }

    static func uri(from value: String, type: String) -> String? {
        let prefix = "spotify:\(type):"
        let identifier: String
        if value.hasPrefix(prefix) {
            identifier = String(value.dropFirst(prefix.count))
        } else {
            guard let components = URLComponents(string: value),
                  ["open.spotify.com", "xpui.app.spotify.com"].contains(components.host),
                  ["https", "http"].contains(components.scheme) else { return nil }
            let parts = components.path.split(separator: "/")
            guard parts.count == 2, parts[0] == type else { return nil }
            identifier = String(parts[1])
        }
        guard identifier.count == 22,
              identifier.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").contains($0)
              }) else { return nil }
        return prefix + identifier
    }
}
