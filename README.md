# Reflex - macOS Spotify Menu Bar Controller

Reflex controls the installed Spotify desktop app without requiring a Spotify developer account or a connection to the Spotify Web API.

## Features

- **Background search/play**: Open the global shortcut, type a song and optionally its artist, and press Return. Reflex sets Spotify's search field through Accessibility and submits Return directly to Spotify's process. It reads the matching track link and presses Play on that exact search-result row. The popup closes without activating another application. Success requires the same track to be playing, not merely loaded and paused.
- **Menu-bar controls**: Play/pause, skip, replay, seek, and adjust volume through local AppleScript and Scripting Bridge.
- **Now playing**: Display locally read track information and artwork.
- **Command palette**: Type `>` in search for restart, navigation, and sleep timer commands.
- **Preferences**: Configure the shortcut, menu-bar display, and launch at login.

The popup does not currently display music search results or recent plays. Queue display, queue insertion, repeat and shuffle commands have been removed. Album and artist navigation opens Spotify search using local metadata. See [the removal record](docs/removals.md) for the intended behavior of removed features and possible future local replacements.

## Requirements and permissions

- macOS 14 or later.
- Spotify desktop app, signed into a Spotify account.
- **Accessibility** permission for Reflex to inspect and operate Spotify's interface during background search/play. Enable Reflex in System Settings → Privacy & Security → Accessibility.
- **Automation** permission to control Spotify when macOS prompts for it.

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

This builds a release executable, assembles and signs the app, replaces `/Applications/Reflex.app`, and launches it. The script uses the local `Reflex Dev` signing identity when available and otherwise falls back to ad-hoc signing. No API credentials or generated credential source are required.

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
