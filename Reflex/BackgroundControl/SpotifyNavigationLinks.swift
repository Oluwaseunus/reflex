import Foundation

/// Links read only from Spotify's now-playing bar, never from search results.
struct SpotifyNowPlayingLink {
    let label: String
    let value: String
}

enum SpotifyNavigationLinks {
    static func uri(for destination: PlaybackNavigation.Destination,
                    state: PlaybackState, links: [SpotifyNowPlayingLink]) -> String? {
        guard state.app?.bundleIdentifier == PlaybackPlayer.spotify.rawValue,
              let title = state.trackName, !normalized(title).isEmpty,
              let artist = state.artistName, !normalized(artist).isEmpty,
              links.contains(where: {
                  normalized($0.label) == normalized(title)
                      && (SpotifySearchIdentity.uri(from: $0.value, type: "album") != nil
                          || SpotifySearchIdentity.uri(from: $0.value, type: "track") != nil)
              }) else { return nil }

        let artists = links.filter { SpotifySearchIdentity.uri(from: $0.value, type: "artist") != nil }
        guard let primary = artists.first else { return nil }
        let names = artists.map(\.label)
        let artistNames = [primary.label] + [", ", " & ", "; "].map { names.joined(separator: $0) }
        guard artistNames.contains(where: { normalized($0) == normalized(artist) }) else { return nil }

        switch destination {
        case .artist:
            return SpotifySearchIdentity.uri(from: primary.value, type: "artist")
        case .album:
            let albums = Set(links.filter { normalized($0.label) == normalized(title) }
                .compactMap { SpotifySearchIdentity.uri(from: $0.value, type: "album") })
            return albums.count == 1 ? albums.first : nil
        case .track:
            return nil
        }
    }

    private static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
