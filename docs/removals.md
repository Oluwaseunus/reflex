# Removed features and implementation

## 2026-09-07: Remove Spotify Web API integration

Decision: Reflex controls the installed Spotify desktop app locally. Search/play uses the existing background Accessibility controller. The Web API and its account authorization were removed because the development-mode user limit does not fit the intended distribution model.

This record preserves feature intent for possible future local implementations. It is not a promise that those features exist in the current build.

| Removed feature or implementation | Original intent | Behavior after removal / possible future work |
| --- | --- | --- |
| Spotify account connection in Preferences | Authorize user-scoped requests using PKCE, browser sign-in, callback state validation, token refresh and Keychain storage. | No account connection inside Reflex. Users sign into the Spotify desktop app. Remove the callback listener, scopes, token code and account UI. |
| API search results | Debounce typed queries and show track/album results with artwork, type labels and keyboard selection. Artist search was advertised but the provider requested tracks and albums only. | Keep typing a query and pressing Return to ask the background Accessibility controller to find and play a song. The old API result loader was already disconnected from ordinary query changes. A future result list needs a local source and exact selection behavior. |
| Result playback and album context | Play a selected track within its album so the album continues afterward; support album/context playback. | Remove the provider and Shift+Return result-playback route. Existing background text search/play remains; it does not promise API-equivalent context selection. |
| Recent plays | Store the last five API-played tracks/albums and replay them from the popup. | Remove the store and recent-result UI; opening the popup already suppressed recents. A future local history should store verified playback identities. |
| Add selected track to queue | Command+Return appended a selected track without replacing current playback, then showed confirmation. | Remove queue submission and its keyboard hint. Local queue insertion is future work. Modified Return has no separate queue action. |
| Menu-bar queue display | Show the next five tracks with artwork and refresh when opening the popover or changing tracks. | Remove queue requests, models, loading/error state, button and rows. A future queue view needs local extraction. |
| Spotify Connect device discovery and transfer | Recover from no active device by launching Spotify, finding devices and transferring playback. | Remove remote device discovery and transfer. Reflex controls the installed desktop app. |
| Repeat current song | Enable single-track repeat from the command palette. | Remove the API command. A local implementation remains future work. |
| Shuffle | Read shuffle state and toggle it from the command palette. | Remove the API command. A local implementation remains future work. |
| API restart command | Seek the current track to zero from the command palette. | Preserve the command through the existing local AppleScript seek helper. Menu-bar seek/replay already work locally. |
| Exact album/artist context lookup | Enrich now-playing data with canonical album and primary-artist URIs and use them for navigation. | Remove API enrichment and its fields. Preserve album/artist navigation using existing Spotify search deep links built from local metadata; these open search rather than an exact entity page. |
| Optimistic API playback state and startup notification | Immediately display the selected result, then delay polling while Spotify starts it. | Remove API-result state publication and its now-orphaned global suppression guard. Keep the independent local track-change grace period in the now-playing view. |
| API error/retry infrastructure | Handle expired tokens, missing Premium, rate limits, networking failures and missing devices. | Remove API-specific errors, banners and retries. Background Accessibility permission/failure handling remains a separate improvement. |
| Build-time API configuration | Generate a Swift client-ID file from the build environment and require it in releases. | Remove the generated file, generator, credential injection and API configuration requirements. Keep build, signing, packaging, installation and relaunch workflows. |
| OAuth incoming-network entitlement | Receive the browser redirect on a loopback HTTP listener. | Remove incoming-network access. Keep outgoing access for artwork URLs supplied by the desktop app; artwork downloading does not call the Spotify Web API. |
| API-only artwork views | Render cover art in removed search results and queue rows. | Remove their unused view wrapper. Preserve now-playing artwork and its shared data cache. |

### Features retained

- Global search shortcut and background Accessibility search/play, including existing focus behavior.
- Local AppleScript and Scripting Bridge controls: play/pause, skip, replay, seeking and volume.
- Locally read now-playing metadata and artwork.
- Command palette navigation, recent command ordering and sleep timers.
- Preferences, launch-at-login setting and menu-bar display options.

### Existing installations

Removal of the source does not revoke previous Spotify authorizations or erase old Keychain items and recent-play preferences. The new implementation does not read or use those records. Users who previously connected Reflex can revoke its access in their Spotify account's app settings. No local secrets or credentials are reproduced in this document.

### Validation scope

Verify compilation, absence of Web API/authentication references in executable source and build workflows, local UI behavior, and the `./save` release/install flow. The existing Accessibility controller still relies on Spotify's exposed interface; removing the Web API does not establish its reliability across Spotify versions or languages.

Validation for this removal: the debug build and `git diff --check` passed. `./save` completed the release build, signing, installation and relaunch. Source/build-workflow scans found no remaining Web API/authentication references; the installed executable contained none of the removed Spotify API endpoints or integration symbols. Computer-use inspection of the installed Reflex app timed out, so live UI and playback behavior were not verified in this pass. At the time of removal, the project had no automated test target.

## Background playback follow-up

The search flow now reads a canonical track URI and artist names from Spotify's Accessibility result rows, then presses Play on the same matched row. This restores exact-track targeting without reintroducing Web API access; album/context selection, queue insertion and recent plays remain removed. Playback verification requires the selected URI and a playing state. Search submission no longer hides Reflex, unhides or unminimizes Spotify, or reactivates the previous app. Track matching and URI validation now have an automated test target.

### Search URL navigation removed (2026-09-08)

The `spotify:search:` URL route was intended to navigate to fresh results without foregrounding Spotify. Installed-app logs showed Spotify became foreground asynchronously despite `NSWorkspace.OpenConfiguration.activates = false`; the foreground check then aborted before playback. Background search now sets the search field through Accessibility, selects Spotify's internal responder and sends Return exclusively to Spotify's process. It does not use URL navigation as a fallback. The original working app must remain foreground; an activation-and-restore workaround is not an acceptable replacement. Explicit album/artist navigation commands remain separate from background query submission.

The first replacement explicitly set `AXFocused` on the input to ensure Return reached search. A live test still reported foreground theft, so that native focus request was removed too. Search submission now presses Spotify's Search button through Accessibility to select the input inside the application, then checks its responder and query before submitting.

The next live test isolated playback as the remaining focus trigger: Spotify stayed in the background through search, but its local `play track` scripting command opened the song's album context and brought Spotify forward. Playback now uses the matched search row's Accessibility Play action instead, avoiding album navigation while retaining exact-URI playback verification and foreground checks. Direct UI tests confirmed both this search-row action and Spotify's Command-K/Shift-Return action play a selected track without leaving their respective search views. The normal search-row action was kept because Reflex can pair its Play button with the canonical track and artist links in the same row. Seven matching tests and the build/install pass. An end-to-end Reflex shortcut test then found the search field, submitted the query, matched a result, pressed its Play button, verified the selected track was playing and completed with the original foreground application preserved.
