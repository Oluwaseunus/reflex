# Reflex - macOS Media Key Router

Reflex is an intelligent macOS menu bar application that routes global media keypresses (play/pause, next, previous) to your preferred media player with smart auto-switching.

## Features

- **Smart Auto-Switching**: Automatically detects which app is playing and routes media keys there
- **Multi-App Support**: Works with Spotify, Apple Music, VLC, and more
- **Quick Switch Menu**: Easily switch between running media apps from the menu bar
- **Rich Status Display**: Shows "Now Playing" info with track details in the menu bar
- **Intelligent App Discovery**: Automatically detects installed media apps
- **Visual Feedback**: Menu bar icon flashes when commands are sent
- **Launch at Login**: Option to start Reflex automatically

## Requirements

- macOS 10.15 (Catalina) or later
- Accessibility permission (required for media key interception)

## Building from Source

### Prerequisites

- Xcode 14.0 or later
- macOS 12.0 or later (for development)

### Setup Instructions

1. **Open Xcode** and create a new project:
   - Select "macOS" → "App"
   - Product Name: `Reflex`
   - Team: Your development team
   - Organization Identifier: `com.yourcompany`
   - Interface: SwiftUI
   - Language: Swift

2. **Configure the project:**
   - Set Deployment Target to macOS 10.15
   - Disable App Sandbox in Signing & Capabilities (required for CGEvent tap)
   - Add "Hardened Runtime" capability

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
│   ├── AccessibilityManager.swift   # Permission handling
│   ├── PreferencesManager.swift     # Preferences persistence
│   ├── MediaAppDetector.swift       # App discovery
│   ├── MediaCommandSender.swift     # AppleScript commands
│   ├── MediaKeyListener.swift       # CGEvent tap
│   ├── SmartRouter.swift            # Routing logic
│   └── StatusBarManager.swift       # Menu bar UI
│
├── UI/
│   ├── StatusBar/
│   │   └── StatusBarView.swift
│   ├── Preferences/
│   │   ├── PreferencesWindow.swift
│   │   ├── GeneralPreferencesView.swift
│   │   ├── AppsPreferencesView.swift
│   │   ├── ShortcutsPreferencesView.swift
│   │   └── AboutPreferencesView.swift
│   └── Onboarding/
│       ├── WelcomeView.swift
│       └── PermissionsGuideView.swift
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

1. **First Launch**: Grant Accessibility permission when prompted
2. **Menu Bar**: Click the music note icon to access controls
3. **Quick Switch**: Select your preferred media app from the popover
4. **Preferences**: Configure auto-switching, favorites, and display options

## Permissions

Reflex requires **Accessibility permission** to intercept media keys. This permission:
- Allows monitoring of Play/Pause, Next, and Previous keys
- Enables routing commands to specific apps
- Is required for the CGEvent tap functionality

To grant permission:
1. Open System Settings → Privacy & Security → Accessibility
2. Click the lock to make changes
3. Enable Reflex in the list

## Supported Apps

- Spotify
- Apple Music
- VLC
- iTunes (legacy)
- Amazon Music
- Tidal
- Deezer
- Audirvana
- Plexamp
- Vox

## Troubleshooting

### Media keys not working
1. Ensure Accessibility permission is granted
2. Check that the target app is running
3. Try restarting Reflex

### App not detected
1. Open Preferences → Apps
2. Check if the app is listed as installed
3. Add it to favorites for quick access

### Commands not sending
1. Verify the app supports AppleScript control
2. Check Console.app for error messages
3. Try restarting the target app

## License

MIT License - See LICENSE file for details.

## Contributing

Contributions are welcome! Please open an issue or pull request on GitHub.
