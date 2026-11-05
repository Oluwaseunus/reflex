import XCTest
@testable import Reflex

final class PlaybackNavigationTests: XCTestCase {
    private func state(_ player: PlaybackPlayer, track: String? = "Song", album: String? = "Album",
                       artist: String? = "Artist") -> PlaybackState {
        let app = MediaApp(id: player.rawValue, name: player.name, bundleIdentifier: player.rawValue,
                           icon: nil, appleScriptName: player.appleScriptName, supportsNowPlaying: true)
        return PlaybackState(app: app, isPlaying: false, trackName: track, artistName: artist,
                             albumName: album, timestamp: Date())
    }

    func testMusicUsesDeepLinksAndSpotifyTrackPreservesPlayback() {
        XCTAssertEqual(PlaybackNavigation.route(to: .track, state: state(.spotify)), .activate)
        for destination in PlaybackNavigation.Destination.allCases {
            XCTAssertEqual(PlaybackNavigation.route(to: destination, state: state(.appleMusic)), .appleMusic(destination))
        }
    }

    func testLocalPersistentIDIsValidatedWithoutConvertingItToALibraryID() {
        XCTAssertTrue(AppleMusicIdentity.isValidPersistentID("CFAFB3150E783CA3"))
        XCTAssertFalse(AppleMusicIdentity.isValidPersistentID("1535018957"))
        XCTAssertFalse(AppleMusicIdentity.isValidPersistentID("0000000000000000"))
        XCTAssertFalse(AppleMusicIdentity.isValidPersistentID("i.eoDzqEgcZxRJJBY"))
        XCTAssertFalse(AppleMusicIdentity.isValidPersistentID(nil))
    }

    func testMusicCatalogIdentityComesFromSongLinksOnly() {
        XCTAssertEqual(AppleMusicIdentity.catalogSongID(from: URL(string: "https://music.apple.com/ng/album/the-art-of-closure/1535018947?i=1535018957")), "1535018957")
        XCTAssertEqual(AppleMusicIdentity.catalogSongID(from: URL(string: "https://music.apple.com/ng/song/empty-love/1535018957")), "1535018957")
        XCTAssertNil(AppleMusicIdentity.catalogSongID(from: URL(string: "https://music.apple.com/ng/album/the-art-of-closure/1535018947")))
        XCTAssertNil(AppleMusicIdentity.catalogSongID(from: URL(string: "https://example.com/ng/song/empty-love/1535018957")))
        XCTAssertNil(AppleMusicIdentity.catalogSongID(from: URL(string: "https://music.apple.com/ng/artist/gracey/1454549634?i=1535018957")))
    }

    func testRelatedAlbumAndArtistLinksAreKeptSeparate() throws {
        let song = CatalogMusicItem(id: "song", name: "Song", url: URL(string: "https://music.apple.com/ng/song/song/123"))
        let album = CatalogMusicItem(id: "album", name: "Album", url: URL(string: "https://music.apple.com/ng/album/album/456"))
        let artist = CatalogMusicItem(id: "artist", name: "Artist", url: URL(string: "https://music.apple.com/ng/artist/artist/789"))
        let details = AppleMusicCatalogDetails(trackKey: "local-id", track: song, albums: [album], artists: [artist], primaryArtistURL: nil)
        XCTAssertEqual(details.url(for: .track), song.url)
        XCTAssertEqual(details.url(for: .album), album.url)
        XCTAssertEqual(details.url(for: .artist), artist.url)
        let ambiguous = AppleMusicCatalogDetails(trackKey: "local-id", track: song, albums: [album, album], artists: [artist], primaryArtistURL: nil)
        XCTAssertNil(ambiguous.url(for: .album))
    }

    func testArtistNavigationPrefersIncludedArtistOverCollaborationURL() throws {
        let artistURL = URL(string: "https://music.apple.com/ng/artist/artist/789")!
        let collaboration = URL(string: "https://music.apple.com/WebObjects/MZStore.woa/wa/viewCollaboration?cc=ng&ids=789,987")!
        let details = AppleMusicCatalogDetails(trackKey: "track",
            track: CatalogMusicItem(id: "123", name: "Song", url: nil), albums: [],
            artists: [CatalogMusicItem(id: "789", name: "Artist", url: artistURL)], primaryArtistURL: collaboration)
        XCTAssertEqual(details.url(for: .artist), artistURL)
        let actualURL = try XCTUnwrap(details.url(for: .artist))
        XCTAssertEqual(AppleMusicDeepLink.url(from: actualURL, destination: .artist)?.absoluteString,
                       "musics://music.apple.com/ng/artist/artist/789")
    }

    func testDeepLinksStripPlaybackAndTrackingParameters() throws {
        let url = try XCTUnwrap(URL(string: "https://music.apple.com/ng/album/album/100?i=123&play=1&uo=4"))
        XCTAssertEqual(AppleMusicDeepLink.url(from: url, destination: .track)?.absoluteString,
                       "musics://music.apple.com/ng/album/album/100?i=123")
        XCTAssertEqual(AppleMusicDeepLink.url(from: url, destination: .album)?.absoluteString,
                       "musics://music.apple.com/ng/album/album/100")
        XCTAssertNil(AppleMusicDeepLink.url(from: URL(string: "https://example.com/album/123")!, destination: .album))
    }

    private func catalogCandidate(id: String = "123", title: String = "Song", artist: String = "Artist",
                                  album: String = "Album", duration: Double = 180, isrc: String? = "ISRC1") -> AppleMusicCatalogCandidate {
        AppleMusicCatalogCandidate(id: id, title: title, artist: artist, album: album, duration: duration, isrc: isrc)
    }

    func testCatalogMatchingNeedsNoLibraryOrLocalIdentity() throws {
        let app = state(.appleMusic).app
        let playing = PlaybackState(app: app, isPlaying: true, trackName: "Song", artistName: "Artist",
                                    albumName: "Album", duration: 180, timestamp: Date())
        XCTAssertNil(playing.trackIdentifier)
        XCTAssertEqual(try AppleMusicCatalogMatch.songID(for: playing, candidates: [catalogCandidate()]), "123")
    }

    func testCatalogMatchRejectsWrongRecordingAndLibraryIDs() throws {
        let playing = PlaybackState(app: state(.appleMusic).app, isPlaying: true, trackName: "Song",
                                    artistName: "Artist", albumName: "Album", duration: 180, timestamp: Date())
        for candidate in [catalogCandidate(title: "Song (Live)"), catalogCandidate(artist: "Other Artist"),
                          catalogCandidate(album: "Other Album"), catalogCandidate(duration: 190),
                          catalogCandidate(id: "i.library-id")] {
            XCTAssertNil(try AppleMusicCatalogMatch.songID(for: playing, candidates: [candidate]))
        }
        XCTAssertEqual(try AppleMusicCatalogMatch.songID(for: playing,
                       candidates: [catalogCandidate(album: "Other Album"), catalogCandidate(id: "456", duration: 180.8)]), "456")
    }

    func testCatalogMatchNormalizesCollaborationSeparatorsAndUnicode() throws {
        let playing = state(.appleMusic, track: "  Song  ", artist: "Artist, Guest & Beyoncé")
        XCTAssertEqual(try AppleMusicCatalogMatch.songID(for: playing,
                       candidates: [catalogCandidate(artist: "Guest, Beyonce\u{301} & Artist")]), "123")
    }

    func testCatalogMatchRejectsAmbiguousRecordingsButAcceptsDuplicateReleases() throws {
        let playing = state(.appleMusic)
        XCTAssertThrowsError(try AppleMusicCatalogMatch.songID(for: playing,
                             candidates: [catalogCandidate(), catalogCandidate(id: "456", isrc: "ISRC2")]))
        XCTAssertThrowsError(try AppleMusicCatalogMatch.songID(for: playing,
                             candidates: [catalogCandidate(), catalogCandidate(id: "456", isrc: nil)]))
        XCTAssertEqual(try AppleMusicCatalogMatch.songID(for: playing,
                       candidates: [catalogCandidate(), catalogCandidate(id: "456")]), "123")
    }

    private var expandedSongJSON: String {
        #"""
        {"id":"123","type":"songs","attributes":{
          "name":"Song","artistName":"Artist","albumName":"Album","durationInMillis":180000,"isrc":"ISRC1",
          "url":"https://music.apple.com/ng/album/album/456?i=123","artistUrl":"https://music.apple.com/ng/artist/artist/789"
        },"relationships":{
          "albums":{"data":[{"id":"456","type":"albums","attributes":{"name":"Album","url":"https://music.apple.com/ng/album/album/456"}}]},
          "artists":{"data":[{"id":"789","type":"artists","attributes":{"name":"Artist","url":"https://music.apple.com/ng/artist/artist/789"}}]}
        }}
        """#
    }

    func testOneSearchRequestReturnsTrackAlbumAndArtistLinks() async throws {
        let playing = state(.appleMusic)
        let fixture = Data(("{\"results\":{\"songs\":{\"data\":[" + expandedSongJSON + "]}}}").utf8)
        var requests: [URLRequest] = []
        let details = try await AppleMusicCatalogRequest.resolve(state: playing, country: "NG") { request in
            requests.append(request)
            return fixture
        }
        XCTAssertEqual(requests.count, 1)
        let components = try XCTUnwrap(URLComponents(url: XCTUnwrap(requests.first?.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/v1/catalog/ng/search")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["term"], "Song Artist Album")
        XCTAssertEqual(query["types"], "songs")
        XCTAssertEqual(query["include[songs]"], "albums,artists")
        XCTAssertEqual(query["extend[songs]"], "artistUrl")
        XCTAssertEqual(details.track.id, "123")
        XCTAssertEqual(details.albums.map(\.id), ["456"])
        XCTAssertEqual(details.artists.map(\.id), ["789"])
        for destination in PlaybackNavigation.Destination.allCases {
            XCTAssertNotNil(details.url(for: destination))
        }
    }

    func testKnownIDLoadsRelationshipsInTheSameRequest() async throws {
        let fixture = Data(("{\"data\":[" + expandedSongJSON + "]}").utf8)
        var requests: [URLRequest] = []
        let details = try await AppleMusicCatalogRequest.resolve(state: state(.appleMusic), country: "ng", directID: "123") { request in
            requests.append(request)
            return fixture
        }
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.path, "/v1/catalog/ng/songs/123")
        let components = try XCTUnwrap(URLComponents(url: XCTUnwrap(requests.first?.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "include" })?.value, "albums,artists")
        XCTAssertNotNil(details.url(for: .album))
        XCTAssertNotNil(details.url(for: .artist))
    }

    func testNoMatchDoesNotTriggerASecondSearch() async {
        var count = 0
        do {
            _ = try await AppleMusicCatalogRequest.resolve(state: state(.appleMusic), country: "ng") { _ in
                count += 1
                return Data(#"{"results":{"songs":{"data":[]}}}"#.utf8)
            }
            XCTFail("Expected no-match error")
        } catch { XCTAssertTrue(error is AppleMusicCatalogError) }
        XCTAssertEqual(count, 1)
    }

    private actor RequestCount {
        var value = 0
        func increment() { value += 1 }
    }

    func testConcurrentLookupsAndLaterClicksReuseOneRequest() async throws {
        let playing = state(.appleMusic)
        let count = RequestCount()
        let fixture = Data(("{\"results\":{\"songs\":{\"data\":[" + expandedSongJSON + "]}}}").utf8)
        let resolver = AppleMusicCatalogResolver { snapshot in
            try await AppleMusicCatalogRequest.resolve(state: snapshot, country: "ng") { _ in
                await count.increment()
                try await Task.sleep(for: .milliseconds(20))
                return fixture
            }
        }
        async let first = resolver.details(for: playing)
        async let second = resolver.details(for: playing)
        let (a, b) = try await (first, second)
        XCTAssertEqual(a, b)
        let cached = try await resolver.details(for: playing)
        XCTAssertEqual(cached, a)
        let requestCount = await count.value
        XCTAssertEqual(requestCount, 1)
    }

    func testSpotifyKeepsMetadataSearchNavigation() {
        let spotify = state(.spotify)
        XCTAssertEqual(PlaybackNavigation.route(to: .album, state: spotify),
                       .spotifySearch(AppleScriptHelper.spotifyAlbumSearchURI(album: "Album", artist: "Artist")))
        XCTAssertEqual(PlaybackNavigation.route(to: .artist, state: spotify),
                       .spotifySearch(AppleScriptHelper.spotifyArtistSearchURI(artist: "Artist")))
    }

    func testSpotifyNowPlayingLinksResolveAlbumAndPrimaryArtist() {
        let albumID = "61PCQeDaTD2gwfpHFikpbh"
        let artistID = "3qiHUAX7zY4Qnjx8TNUzVx"
        let links = [
            SpotifyNowPlayingLink(label: "Song", value: "https://xpui.app.spotify.com/album/\(albumID)"),
            SpotifyNowPlayingLink(label: "Artist", value: "https://xpui.app.spotify.com/artist/\(artistID)")
        ]
        XCTAssertEqual(SpotifyNavigationLinks.uri(for: .album, state: state(.spotify), links: links), "spotify:album:\(albumID)")
        XCTAssertEqual(SpotifyNavigationLinks.uri(for: .artist, state: state(.spotify), links: links), "spotify:artist:\(artistID)")
        XCTAssertNil(SpotifyNavigationLinks.uri(for: .track, state: state(.spotify), links: links))
        XCTAssertNil(SpotifyNavigationLinks.uri(for: .album, state: state(.appleMusic), links: links))
        XCTAssertNil(SpotifyNavigationLinks.uri(for: .album, state: state(.spotify, track: "Other song"), links: links))
        XCTAssertNil(SpotifyNavigationLinks.uri(for: .artist, state: state(.spotify, artist: "Other artist"), links: links))
    }

    func testSpotifyLinksRejectAmbiguousAlbumsAndUntrustedHosts() {
        let artist = SpotifyNowPlayingLink(label: "Artist", value: "spotify:artist:3qiHUAX7zY4Qnjx8TNUzVx")
        let first = SpotifyNowPlayingLink(label: "Song", value: "spotify:album:61PCQeDaTD2gwfpHFikpbh")
        let second = SpotifyNowPlayingLink(label: "Song", value: "spotify:album:3qiHUAX7zY4Qnjx8TNUzVx")
        XCTAssertNil(SpotifyNavigationLinks.uri(for: .album, state: state(.spotify), links: [first, second, artist]))
        let untrusted = SpotifyNowPlayingLink(label: "Song", value: "https://example.com/album/61PCQeDaTD2gwfpHFikpbh")
        XCTAssertNil(SpotifyNavigationLinks.uri(for: .album, state: state(.spotify), links: [untrusted, artist]))
        let collaborator = SpotifyNowPlayingLink(label: "Guest", value: "spotify:artist:1260748364aaaaaaaaaaaa")
        XCTAssertEqual(SpotifyNavigationLinks.uri(for: .artist, state: state(.spotify, artist: "Artist, Guest"),
                                                 links: [first, artist, collaborator]), artist.value)
    }

    func testSpotifySearchFallbackEncodesReservedCharacters() {
        let uri = AppleScriptHelper.spotifyAlbumSearchURI(album: "A & B? #1/2", artist: "Beyoncé")
        let encoded = String(uri.dropFirst("spotify:search:".count))
        XCTAssertEqual(encoded.removingPercentEncoding, "album:A & B? #1/2 artist:Beyoncé")
        XCTAssertFalse(encoded.contains("&"))
        XCTAssertFalse(encoded.contains("#"))
        XCTAssertFalse(encoded.contains("?"))
        XCTAssertFalse(encoded.contains("/"))
    }

    func testMissingMetadataOnlyDisablesCorrespondingDestination() {
        let music = state(.appleMusic, album: " \n", artist: nil)
        XCTAssertNotNil(PlaybackNavigation.route(to: .track, state: music))
        XCTAssertNil(PlaybackNavigation.route(to: .album, state: music))
        XCTAssertNil(PlaybackNavigation.route(to: .artist, state: music))
        for destination in PlaybackNavigation.Destination.allCases {
            XCTAssertNil(PlaybackNavigation.route(to: destination, state: state(.appleMusic, track: nil)))
        }
    }

    @MainActor
    func testMusicNavigationCommandsAreEnabledWithoutEnablingSleepTimers() {
        let manager = PlaybackStateManager()
        manager.updateState(state(.appleMusic))
        let model = SearchViewModel(stateManager: manager)
        model.onQueryChanged(">")
        guard case .commands(let commands) = model.state else { return XCTFail("Expected command palette") }
        for kind in [SearchCommandKind.goToTrack, .goToAlbum, .goToArtist] {
            XCTAssertEqual(commands.first { $0.kind == kind }?.isEnabled, true)
        }
        XCTAssertEqual(commands.first { $0.kind == .sleepTimer5Minutes }?.isEnabled, false)
    }
}
