# Reflex - macOS Spotify Menu Bar Controller

Reflex is a macOS menu bar application for controlling Spotify playback, search, and queue access without switching away from your current app.

## Features

- **Spotify Search**: Find tracks, albums, and artists from a global shortcut
- **Menu Bar Controls**: Play, pause, skip, scrub, and adjust Spotify playback
- **Queue View**: See upcoming Spotify tracks from the menu bar
- **Rich Status Display**: Shows "Now Playing" info with track details in the menu bar
- **Launch at Login**: Option to start Reflex automatically

## Requirements

- macOS 14 or later
- Spotify desktop app
- Spotify account authorization for search, playback, and queue features

## Building from Source

### Prerequisites

- Xcode 15.0 or later
- macOS 14.0 or later (for development)

### Setup Instructions

1. **Open Xcode** and create a new project:
   - Select "macOS" → "App"
   - Product Name: `Reflex`
   - Team: Your development team
   - Organization Identifier: `com.yourcompany`
   - Interface: SwiftUI
   - Language: Swift

2. **Configure the project:**
   - Set Deployment Target to macOS 14
   - Enable App Sandbox in Signing & Capabilities
   - Add Apple Events automation, outgoing network, and incoming network entitlements

3. **Import source files:**
   - Delete the default `ContentView.swift` and `ReflexApp.swift`
   - Drag all files from the `Reflex/` folder into your Xcode project
   - Make sure "Copy items if needed" is checked

4. **Configure Info.plist:**
   - Replace the generated Info.plist with the provided one
   - Or merge the keys from the provided Info.plist

5. **Add Resources:**
   - Add `MediaAppDefinitions.json` to the project
   - Ensure it's included in "Copy Bundle Resources" build phase

6. **Configure Entitlements:**
   - Add the provided `Reflex.entitlements` file
   - Set it in Build Settings → Code Signing Entitlements

7. **Build and Run:**
   - Select your Mac as the destination
   - Build (⌘B) and Run (⌘R)

### Project Structure

```
Reflex/
├── ReflexApp.swift              # Main app entry point
├── Info.plist                   # App configuration
├── Reflex.entitlements          # App entitlements
│
├── Models/
│   ├── MediaApp.swift           # Media app model
│   ├── MediaCommand.swift       # Command definitions
│   ├── PlaybackState.swift      # Playback state tracking
│   └── AppPreferences.swift     # User preferences
│
├── Managers/
│   ├── PreferencesManager.swift     # Preferences persistence
│   ├── MediaAppDetector.swift       # App discovery
│   ├── MediaCommandSender.swift     # AppleScript commands
│   ├── SmartRouter.swift            # Spotify command logic
│   ├── SpotifyBridge.swift          # Spotify API bridge
│   └── StatusBarManager.swift       # Menu bar UI
│
├── Spotify/
│   ├── SpotifyAuthManager.swift
│   ├── SpotifyPlaybackProvider.swift
│   ├── SpotifySearchProvider.swift
│   └── SpotifyUserAPI.swift
│
├── UI/
│   ├── StatusBar/
│   │   └── StatusBarView.swift
│   ├── Preferences/
│   │   ├── PreferencesWindow.swift
│   │   ├── GeneralPreferencesView.swift
│   │   ├── ShortcutsPreferencesView.swift
│   │   └── AboutPreferencesView.swift
│   └── Onboarding/
│       └── WelcomeView.swift
│
├── Utilities/
│   ├── Constants.swift
│   ├── Logger.swift
│   └── AppleScriptHelper.swift
│
└── Resources/
    └── MediaAppDefinitions.json
```

## Usage

1. **First Launch**: Connect your Spotify account in Preferences
2. **Menu Bar**: Click the music note icon to access playback controls
3. **Search**: Use the configured global shortcut to open Spotify search
4. **Preferences**: Configure launch, display, feedback, and shortcut options

## Permissions

Reflex uses Apple Events automation to control Spotify playback through AppleScript. macOS may prompt you to allow Reflex to control Spotify the first time a playback command is sent.

## Supported Apps

- Spotify

## Troubleshooting

### Spotify controls not working
1. Ensure Spotify is installed and running
2. Allow Apple Events automation if macOS prompts for it
3. Try restarting Reflex and Spotify

### Search is unavailable
1. Open Preferences → General
2. Connect your Spotify account
3. Confirm this build includes Spotify API credentials

### Commands not sending
1. Verify Spotify responds to AppleScript control
2. Check Console.app for error messages
3. Try restarting Spotify

## License

MIT License - See LICENSE file for details.

## Contributing

Contributions are welcome! Please open an issue or pull request on GitHub.
