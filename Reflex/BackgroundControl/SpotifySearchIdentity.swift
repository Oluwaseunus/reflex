import Foundation

/// Identity extracted from a Spotify Accessibility result, not a network API.
struct SpotifySearchIdentity {
    let trackURI: String
    let title: String
    let artists: [String]

    func score(for query: String) -> Int? {
        let queryWords = Self.words(query).filter { !["by", "feat", "featuring"].contains($0) }
        guard !queryWords.isEmpty else { return nil }
        let titleWords = Self.words(title)
        let artistWords = artists.flatMap(Self.words)
        let available = Set(titleWords + artistWords)
        guard queryWords.allSatisfy(available.contains) else { return nil }
        // Prefer a complete title over a remix/alternate version with extra words.
        let exactTitle = titleWords == queryWords
        let titleAndArtist = titleWords + artistWords == queryWords
        return (exactTitle ? 1_000 : 0) + (titleAndArtist ? 1_000 : 0)
            + queryWords.filter(Set(titleWords).contains).count * 10 - titleWords.count
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

    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
