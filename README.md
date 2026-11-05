# Reflex - macOS Music Menu Bar Controller

Reflex controls the installed Spotify or Apple Music app. Choose the player in Settings → General → Music player, or select Automatic to follow the player that most recently starts playing. Explicit player choices stay fixed.

Both players use shared now-playing state and support playback, previous/restart, seeking, volume and mute. Switching players clears the previous track and artwork. Volume updates live while dragging in both players; Apple Music seek drags commit when released.

Apple Music navigation uses MusicKit to match the current song and load its album and artist relationships, including catalog IDs and URLs. Resolved details are cached alongside the current playback state. Deep links open the catalog destination without menu automation. The local Music persistent ID remains separate from MusicKit catalog IDs. Apple Music search, sleep-timer/restart palette actions and AirPlay selection are not implemented yet.

### Apple Music / MusicKit setup

- Enable the MusicKit App Service for the explicit `com.oluwaseun.reflex.app` App ID in the Apple Developer portal.
- Use an Apple-issued signing identity belonging to that App ID’s team. `./save` prefers an available Developer ID Application identity and falls back to self-signed local development when none is available. Set `REFLEX_SIGN_IDENTITY` to an exact certificate name to choose explicitly; MusicKit testing requires the Apple-issued identity.
- In Reflex Settings → Permissions, click **Connect Apple Music** and approve the macOS request. **Check Connection** verifies the MusicKit connection. Both the Xcode and local installer Info.plists include the required `NSAppleMusicUsageDescription`.
- MusicKit is an App Service, not a `com.apple.developer.musickit` entitlement. No private key or manually managed developer token is embedded in Reflex.
- MusicKit handles catalog authentication and storefront selection. No public iTunes Search API lookup remains.
- Apple Music navigation uses an exact catalog URL when available; otherwise it queries the Apple Music catalog and matches the current track’s title, artists, album and duration. The same catalog request includes the song’s album and artist relationships; there is no follow-up relationship request or automatic second search. Concurrent lookups for the same track share one request, and successful results are cached. Saved-library membership is not required. Ambiguous recordings are rejected, and navigation opens catalog deep links without menu automation or clipboard access.
- Desktop playback observation/control still uses local AppleScript and Scripting Bridge: MusicKit’s SystemMusicPlayer is unavailable on macOS, while ApplicationMusicPlayer would play inside Reflex instead of controlling Music.


Spotify integration requires no Spotify developer account or connection to the Spotify Web API.
Album and artist navigation reads exact links from Spotify's now-playing bar using Accessibility. If those links are unavailable or stale, it falls back to a metadata search in Spotify.

## Features

- **Background search/play**: Open the global shortcut, type a song and optionally its artist, and press Return. Reflex sets Spotify's search field through Accessibility and submits Return directly to Spotify's process. It reads the matching track link and presses Play on that exact search-result row. The popup closes without activating another application. Success requires the same track to be playing, not merely loaded and paused.
- **Menu-bar controls**: Play/pause, skip, replay, seek, and adjust volume through local AppleScript and Scripting Bridge.
- **Now playing**: Display locally read track information and artwork.
- **Automatic player selection**: Follow Spotify or Apple Music when it starts playing, keep that player selected when paused, and remember the last detected player across launches. Explicit player choices stay fixed.
- **Spotify playback devices**: Discover and switch devices through the local Spotify interface.
- **Command palette (Spotify)**: Type `>` in search for restart, navigation, and sleep timer commands.
- **Preferences**: Configure the shortcut, menu-bar display, and launch at login.

The popup does not currently display music search results or recent plays. Queue display, queue insertion, repeat and shuffle commands have been removed. Album and artist navigation opens Spotify search using local metadata. See [the removal record](docs/removals.md) for the intended behavior of removed features and possible future local replacements.

## Requirements and permissions

- macOS 14 or later.
- Spotify desktop app signed into a Spotify account, or the macOS Music app with playable music.
- **Accessibility** permission for Reflex to inspect and operate Spotify's interface during background search/play. Enable Reflex in System Settings → Privacy & Security → Accessibility.
- **Automation** permission to control the selected player when macOS prompts for it. Access can also be requested in Settings → Permissions.

Spotify's Accessibility layout can change. Search-field discovery currently uses English labels; the result matcher reads track and artist links rather than Play-button labels. Other Spotify interface languages are not currently verified. Background search failures currently appear in Console logs; a visible recovery flow remains to be implemented.

## Build and run

Open the included `Reflex.xcodeproj` to build in Xcode, or compile the Swift package:

```sh
swift build
```

For the local development installation:

```sh
./save
```

This builds a release executable, assembles and signs the app, replaces `/Applications/Reflex.app`, and launches it. The script prefers a Developer ID Application signing identity, then the local `Reflex Dev` identity, and finally ad-hoc signing. No API credentials or generated credential source are required.

The Xcode build uses `Reflex/Reflex.entitlements`; the local installer signs without those entitlements.

### Local distribution build

To create a DMG that Gatekeeper accepts on other Macs, store notarization credentials once:

```sh
xcrun notarytool store-credentials reflex-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Then build, sign, notarize, and staple the distributable DMG:

```sh
NOTARY_KEYCHAIN_PROFILE=reflex-notary Scripts/build-dist.sh
```

If more than one Developer ID Application certificate is installed, set `SIGN_IDENTITY` explicitly. The finished artifact is written to `dist/Reflex.dmg`.

## Code layout

- `Reflex/BackgroundControl/`: background Spotify Accessibility search/play.
- `Reflex/Managers/`: local app detection, playback routing, Scripting Bridge, preferences and menu-bar management.
- `Reflex/UI/SearchPopup/`: shortcut panel and local command palette.
- `Reflex/UI/StatusBar/`: now-playing display and playback controls.
- `Reflex/Utilities/`: local AppleScript helpers, artwork cache, logging and constants.
- `docs/removals.md`: removed features, original intentions and retained behavior.

## Troubleshooting

For background search, check Accessibility permission, Spotify's signed-in state and interface language. For playback controls, check Automation permission. Look for Reflex messages in Console when a command fails.

Artwork may be downloaded from the artwork URL supplied by the local Spotify app. This does not use Spotify's Web API.
