# Reflex - macOS Media Key Router

---

## Implementation Status

**Last Updated:** December 9, 2024

### Completed Items (13/17)

| Phase | Task | Status |
|-------|------|--------|
| 0 | Create Xcode project structure | ✅ Complete |
| 0 | Configure Info.plist | ✅ Complete |
| 0 | Create project folder structure | ✅ Complete |
| 1 | Implement core models (MediaApp, MediaCommand, PlaybackState, AppPreferences) | ✅ Complete |
| 1 | Implement utilities (Logger, Constants, AppleScriptHelper) | ✅ Complete |
| 1 | Create MediaAppDefinitions.json | ✅ Complete |
| 2 | Implement AccessibilityManager | ✅ Complete |
| 2 | Implement PreferencesManager | ✅ Complete |
| 2 | Implement MediaAppDetector | ✅ Complete |
| 2 | Implement MediaCommandSender | ✅ Complete |
| 2 | Implement MediaKeyListener (CGEvent tap) | ✅ Complete |
| 2 | Implement SmartRouter | ✅ Complete |
| 3 | Implement StatusBarManager | ✅ Complete |
| 3 | Create StatusBarView (popover) | ✅ Complete |
| 3 | Create PreferencesWindow with all tabs | ✅ Complete |
| 3 | Create onboarding flow (WelcomeView, PermissionsGuideView) | ✅ Complete |
| 4 | Wire up ReflexApp entry point | ✅ Complete |

### Remaining Items (4/17)

| Phase | Task | Status | Notes |
|-------|------|--------|-------|
| 0 | Add App Icon Assets | ⏳ Pending | Need to create 1024x1024 icon and menu bar icon |
| 5 | Test media key capture | ⏳ Pending | Requires Xcode project setup |
| 5 | Test with real apps (Spotify, Apple Music, VLC) | ⏳ Pending | Requires built app |
| 6 | Code signing & distribution prep | ⏳ Pending | Requires Apple Developer account |

### Files Created (26 total)

```
Reflex/
├── ReflexApp.swift                          ✅
├── Info.plist                               ✅
├── Reflex.entitlements                      ✅
├── Models/
│   ├── MediaApp.swift                       ✅
│   ├── MediaCommand.swift                   ✅
│   ├── PlaybackState.swift                  ✅
│   └── AppPreferences.swift                 ✅
├── Managers/
│   ├── AccessibilityManager.swift           ✅
│   ├── PreferencesManager.swift             ✅
│   ├── MediaAppDetector.swift               ✅
│   ├── MediaCommandSender.swift             ✅
│   ├── MediaKeyListener.swift               ✅
│   ├── SmartRouter.swift                    ✅
│   └── StatusBarManager.swift               ✅
├── UI/
│   ├── StatusBar/
│   │   └── StatusBarView.swift              ✅
│   ├── Preferences/
│   │   ├── PreferencesWindow.swift          ✅
│   │   ├── GeneralPreferencesView.swift     ✅
│   │   ├── AppsPreferencesView.swift        ✅
│   │   ├── ShortcutsPreferencesView.swift   ✅
│   │   └── AboutPreferencesView.swift       ✅
│   └── Onboarding/
│       ├── WelcomeView.swift                ✅
│       └── PermissionsGuideView.swift       ✅
├── Utilities/
│   ├── Constants.swift                      ✅
│   ├── Logger.swift                         ✅
│   └── AppleScriptHelper.swift              ✅
└── Resources/
    └── MediaAppDefinitions.json             ✅
```

---

## Next Steps to Complete the Project

### Step 1: Create Xcode Project (Required)

Since the source files are created but not in an Xcode project yet:

1. **Open Xcode** and select "Create a new Xcode project"
2. Choose **macOS → App**
3. Configure:
   - Product Name: `Reflex`
   - Team: Your Apple Developer team (or Personal Team)
   - Organization Identifier: `com.yourcompany` (replace with yours)
   - Interface: **SwiftUI**
   - Language: **Swift**
4. Save the project to a temporary location

5. **Import Source Files:**
   - Delete the auto-generated `ContentView.swift` and `ReflexApp.swift`
   - Drag all files from `/Users/oluwaseunus/Documents/Work/reflex/Reflex/` into Xcode
   - Check "Copy items if needed"
   - Ensure all `.swift` files are added to the target

6. **Add Resources:**
   - Ensure `MediaAppDefinitions.json` is in the target's "Copy Bundle Resources" build phase
   - Verify in Build Phases → Copy Bundle Resources

### Step 2: Configure Build Settings (Required)

1. **Disable App Sandbox:**
   - Select project in navigator → Signing & Capabilities
   - Remove "App Sandbox" if present (click the X)
   - Or: Set `com.apple.security.app-sandbox` to `false` in entitlements

2. **Add Hardened Runtime:**
   - Click "+ Capability"
   - Add "Hardened Runtime"

3. **Set Entitlements:**
   - In Build Settings, search for "Code Signing Entitlements"
   - Set to `Reflex/Reflex.entitlements`

4. **Verify Info.plist:**
   - Ensure the provided Info.plist is being used
   - Or merge keys into the generated one

5. **Set Deployment Target:**
   - Set macOS Deployment Target to 10.15

### Step 3: Create App Icons (Recommended)

1. **Main App Icon (1024x1024):**
   - Create or commission a music-themed icon
   - Can use SF Symbols as inspiration: `music.note.circle.fill`
   - Export all sizes for AppIcon.appiconset

2. **Menu Bar Icon (22x22 template):**
   - Create monochrome PNG
   - Name it with `Template` suffix for automatic dark/light mode
   - Example: `StatusBarIconTemplate.png` and `StatusBarIconTemplate@2x.png`

3. **Add to Assets.xcassets:**
   - Add AppIcon set
   - Add Image Set for status bar icon

### Step 4: Build and Test

1. **Build the project** (⌘B)
   - Fix any compilation errors
   - Most likely issues: missing imports or type mismatches

2. **Run the app** (⌘R)
   - Grant Accessibility permission when prompted
   - Test menu bar icon appears
   - Test popover opens on click

3. **Test Core Functionality:**
   - [ ] Media keys are captured (play/pause, next, previous)
   - [ ] Commands are sent to Spotify/Apple Music/VLC
   - [ ] Auto-switching works between apps
   - [ ] Preferences save and load correctly
   - [ ] Onboarding flow completes properly

### Step 5: Distribution (Optional)

1. **Code Signing:**
   ```bash
   codesign --deep --force --verify --verbose \
     --sign "Developer ID Application: Your Name (TEAMID)" \
     Reflex.app
   ```

2. **Notarization:**
   ```bash
   # Create ZIP or DMG
   ditto -c -k --keepParent Reflex.app Reflex.zip

   # Submit for notarization
   xcrun notarytool submit Reflex.zip \
     --apple-id your@email.com \
     --team-id TEAMID \
     --password APP_SPECIFIC_PASSWORD \
     --wait

   # Staple the ticket
   xcrun stapler staple Reflex.app
   ```

3. **Create DMG:**
   ```bash
   hdiutil create -volname "Reflex" \
     -srcfolder Reflex.app \
     -ov -format UDZO \
     Reflex.dmg
   ```

---

## Potential Issues and Solutions

### Issue: CGEvent tap not working
**Solution:** Ensure Accessibility permission is granted in System Settings → Privacy & Security → Accessibility

### Issue: AppleScript commands failing
**Solution:**
- Check Console.app for errors
- Verify target app is running
- Some apps may need Automation permission

### Issue: App doesn't appear in menu bar
**Solution:** Check that `LSUIElement` is `true` in Info.plist

### Issue: Build errors with SwiftUI views
**Solution:** Ensure deployment target is 10.15+ and all `@EnvironmentObject` dependencies are provided

---

## Project Overview

**Reflex** is a macOS menu bar application that intelligently routes global media keypresses (play/pause, next, previous) to the user's preferred media player. The app features smart auto-switching between playing apps, multi-app management, rich status display, and seamless conflict resolution with system defaults.

**Tech Stack:**
- Language: Swift + Objective-C bridging (where needed)
- UI: SwiftUI + AppKit (for status bar)
- Event Capture: CGEvent tap (requires Accessibility permissions)
- App Detection: NSWorkspace + AppleScript
- Command Routing: AppleScript (best compatibility)
- Minimum macOS: 10.15 (Catalina)

**Project Location:** `/Users/oluwaseunus/Documents/Work/reflex/`

---

## Core Requirements

1. **Background App** - Runs as menu bar app (LSUIElement=true, no Dock icon)
2. **Global Media Key Capture** - Intercept play/pause (F7), next (F9), previous (F8)
3. **Command Routing** - Route captured keys to user-selected media player
4. **Menu Bar Interface** - Status bar icon with popover for app selection
5. **Multi-App Support** - Spotify, Apple Music, VLC, YouTube Music, etc.

---

## Enhanced Features (All Approved)

1. **Smart Auto-Switching** - Automatically detect which app is playing and route there
2. **Multi-App Management** - Multiple favorites with quick-switch menu
3. **Rich Status Display** - Show "Now Playing: App" and track info in menu bar
4. **Intelligent App Discovery** - Auto-scan for installed media apps
5. **Better UX** - Guided permissions setup, visual feedback, launch at login
6. **Enhanced Media Controls** - Volume keys support (optional)
7. **Conflict Resolution** - Gracefully handle macOS default media routing

---

## TODO List

### Phase 0: Project Setup & Foundation

#### TODO 0.1: Create Xcode Project
**Intent:** Initialize the macOS application project structure
**Implementation:**
- Create new macOS App in Xcode named "Reflex"
- Bundle ID: `com.yourcompany.reflex` (replace with actual)
- Language: Swift, Interface: SwiftUI
- Minimum deployment: macOS 10.15
- Disable sandboxing (required for CGEvent tap)
- Configure build settings: enable Hardened Runtime

#### TODO 0.2: Configure Info.plist
**Intent:** Set up required permissions and app behavior
**Implementation:**
Add these keys to `Info.plist`:
```xml
<key>LSUIElement</key><true/>  <!-- Hide from Dock -->
<key>NSAppleEventsUsageDescription</key>
<string>Reflex sends AppleScript commands to control media playback.</string>
<key>NSAccessibilityUsageDescription</key>
<string>Reflex needs Accessibility permission to intercept media key presses.</string>
<key>CFBundleIdentifier</key><string>com.yourcompany.reflex</string>
<key>LSMinimumSystemVersion</key><string>10.15</string>
```

#### TODO 0.3: Create Project Structure
**Intent:** Organize code into logical folders for maintainability
**Implementation:**
Create folders in Xcode project:
```
Reflex/
├── ReflexApp.swift (entry point)
├── Models/
├── Managers/
├── UI/
│   ├── StatusBar/
│   ├── Preferences/
│   └── Onboarding/
├── Utilities/
└── Resources/
```

#### TODO 0.4: Add App Icon Assets
**Intent:** Provide visual branding for the app
**Implementation:**
- Create AppIcon.appiconset with 1024x1024 master
- Create StatusBarIcon (22x22 monochrome template image)
- Use music/media theme (music note or waveform)
- Add to Assets.xcassets

---

### Phase 1: Core Models & Utilities

#### TODO 1.1: Implement MediaApp Model
**File:** `Reflex/Models/MediaApp.swift`
**Intent:** Define data structure representing a media application
**Implementation:**
```swift
struct MediaApp: Identifiable, Codable, Equatable {
    let id: String                    // Bundle identifier
    let name: String                  // Display name (e.g., "Spotify")
    let bundleIdentifier: String      // e.g., "com.spotify.client"
    let icon: String?                 // SF Symbol name or asset
    let appleScriptName: String       // Name for AppleScript (e.g., "Spotify")
    let supportsNowPlaying: Bool      // Can query track info
    var isFavorite: Bool = false
    var isInstalled: Bool = false
    var isRunning: Bool = false
}
```
- Codable for JSON decoding and UserDefaults
- Equatable for comparison and filtering
- Track runtime state (installed/running) separately from static metadata

#### TODO 1.2: Implement MediaCommand Enum
**File:** `Reflex/Models/MediaCommand.swift`
**Intent:** Define all supported media commands with key mappings
**Implementation:**
```swift
enum MediaCommand {
    case playPause, nextTrack, previousTrack, volumeUp, volumeDown, stop

    var keyCode: Int {
        // NX_KEYTYPE values: play=16, next=17, prev=18, volUp=1, volDown=2
    }

    var appleScriptCommand: String {
        // Return AppleScript verb: "playpause", "next track", etc.
    }
}
```
- Map macOS media key codes to commands
- Provide AppleScript command strings for each action

#### TODO 1.3: Implement PlaybackState Model
**File:** `Reflex/Models/PlaybackState.swift`
**Intent:** Track current playback state for UI reactivity
**Implementation:**
```swift
struct PlaybackState {
    let app: MediaApp?
    let isPlaying: Bool
    let trackName: String?
    let artistName: String?
    let timestamp: Date
}

class PlaybackStateManager: ObservableObject {
    @Published var currentState: PlaybackState?
    @Published var activeApp: MediaApp?
}
```
- ObservableObject for SwiftUI automatic UI updates
- Timestamp for staleness detection (>30s = stale)

#### TODO 1.4: Implement AppPreferences Model
**File:** `Reflex/Models/AppPreferences.swift`
**Intent:** User settings with sensible defaults
**Implementation:**
```swift
struct AppPreferences: Codable {
    var favoriteApps: [String] = []           // Array of bundle IDs
    var lastUsedApp: String?                  // Bundle ID
    var autoSwitchEnabled: Bool = true
    var showNowPlaying: Bool = true
    var showTrackInfo: Bool = false
    var launchAtLogin: Bool = false
    var enableVolumeKeys: Bool = true
    var fallbackToSystem: Bool = true
    var customShortcuts: [String: String] = [:] // Future use
}
```

#### TODO 1.5: Create MediaAppDefinitions.json
**File:** `Reflex/Resources/MediaAppDefinitions.json`
**Intent:** Database of supported media apps with metadata
**Implementation:**
```json
[
  {
    "id": "com.spotify.client",
    "name": "Spotify",
    "bundleIdentifier": "com.spotify.client",
    "icon": "music.note",
    "appleScriptName": "Spotify",
    "supportsNowPlaying": true
  },
  {
    "id": "com.apple.Music",
    "name": "Apple Music",
    "bundleIdentifier": "com.apple.Music",
    "icon": "music.note.list",
    "appleScriptName": "Music",
    "supportsNowPlaying": true
  },
  {
    "id": "org.videolan.vlc",
    "name": "VLC",
    "bundleIdentifier": "org.videolan.vlc",
    "icon": "play.rectangle",
    "appleScriptName": "VLC",
    "supportsNowPlaying": true
  }
]
```
- Load at startup and merge with user preferences
- Extensible for community contributions

#### TODO 1.6: Implement Logger Utility
**File:** `Reflex/Utilities/Logger.swift`
**Intent:** Centralized logging with categories for debugging
**Implementation:**
```swift
import os.log

class Logger {
    static let shared = Logger()
    private let logger = os.Logger(subsystem: "com.yourcompany.reflex", category: "main")

    func info(_ message: String) { logger.info("\(message)") }
    func debug(_ message: String) { logger.debug("\(message)") }
    func error(_ message: String, error: Error? = nil) {
        logger.error("\(message) \(String(describing: error))")
    }
}
```
- Use unified logging (os.log) for performance
- Categories: main, events, applescript, permissions

#### TODO 1.7: Implement Constants
**File:** `Reflex/Utilities/Constants.swift`
**Intent:** Centralize magic strings and values
**Implementation:**
```swift
enum Constants {
    enum Notifications {
        static let mediaKeyPressed = "mediaKeyPressed"
        static let playbackStateChanged = "playbackStateChanged"
    }
    enum UserDefaultsKeys {
        static let preferences = "app_preferences"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }
    enum MediaKeyCodes {
        static let play: Int = 16
        static let next: Int = 17
        static let previous: Int = 18
        static let volumeUp: Int = 1
        static let volumeDown: Int = 2
    }
}
```

#### TODO 1.8: Implement AppleScriptHelper
**File:** `Reflex/Utilities/AppleScriptHelper.swift`
**Intent:** Wrapper for NSAppleScript execution with error handling
**Implementation:**
```swift
class AppleScriptHelper {
    static func execute(_ script: String) -> (success: Bool, output: String?, error: Error?) {
        let appleScript = NSAppleScript(source: script)
        var errorDict: NSDictionary?
        let output = appleScript?.executeAndReturnError(&errorDict)

        if let error = errorDict {
            return (false, nil, NSError(domain: "AppleScript", code: -1, userInfo: error as? [String: Any]))
        }
        return (true, output?.stringValue, nil)
    }

    static func checkIfAppIsPlaying(_ app: MediaApp) -> Bool {
        let script = """
        tell application "\(app.appleScriptName)"
            return player state is playing
        end tell
        """
        let result = execute(script)
        return result.output?.contains("true") ?? false
    }

    static func getCurrentTrack(from app: MediaApp) -> (track: String?, artist: String?) {
        // Query current track info via AppleScript
    }
}
```
- 3-second timeout for all scripts
- Parse AppleScript errors gracefully
- Handle app-not-running errors

---

### Phase 2: Core Managers (Business Logic)

#### TODO 2.1: Implement AccessibilityManager
**File:** `Reflex/Managers/AccessibilityManager.swift`
**Intent:** Handle Accessibility permission checks and requests
**Implementation:**
```swift
import Cocoa

class AccessibilityManager: ObservableObject {
    static let shared = AccessibilityManager()
    @Published var hasPermission: Bool = false

    func checkPermission() -> Bool {
        hasPermission = AXIsProcessTrusted()
        return hasPermission
    }

    func requestPermission() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true
        ]
        AXIsProcessTrustedWithOptions(options)
    }

    func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
```
- Check permission status with `AXIsProcessTrusted()`
- Prompt user to grant via `kAXTrustedCheckOptionPrompt`
- Provide direct link to System Preferences

#### TODO 2.2: Implement PreferencesManager
**File:** `Reflex/Managers/PreferencesManager.swift`
**Intent:** Persist user preferences via UserDefaults with type safety
**Implementation:**
```swift
class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    @Published var prefs: AppPreferences {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Constants.UserDefaultsKeys.preferences),
           let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data) {
            self.prefs = decoded
        } else {
            self.prefs = AppPreferences()
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(encoded, forKey: Constants.UserDefaultsKeys.preferences)
        }
    }

    func addFavorite(_ appId: String) { /* ... */ }
    func removeFavorite(_ appId: String) { /* ... */ }
    func setLastUsedApp(_ appId: String) { prefs.lastUsedApp = appId }
}
```
- Auto-save on any change via `didSet`
- Codable for JSON serialization
- Type-safe accessors

#### TODO 2.3: Implement MediaAppDetector
**File:** `Reflex/Managers/MediaAppDetector.swift`
**Intent:** Discover installed apps and monitor running state
**Implementation:**
```swift
class MediaAppDetector: ObservableObject {
    @Published var availableApps: [MediaApp] = []
    @Published var runningApps: [MediaApp] = []

    private let workspace = NSWorkspace.shared

    init() {
        loadAppDefinitions()      // Load from JSON
        detectInstalledApps()     // Check which are installed
        startMonitoring()         // Watch for launches/terminations
    }

    private func loadAppDefinitions() {
        guard let url = Bundle.main.url(forResource: "MediaAppDefinitions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let apps = try? JSONDecoder().decode([MediaApp].self, from: data) else {
            return
        }
        availableApps = apps
    }

    private func detectInstalledApps() {
        for i in 0..<availableApps.count {
            if workspace.urlForApplication(withBundleIdentifier: availableApps[i].bundleIdentifier) != nil {
                availableApps[i].isInstalled = true
            }
        }
    }

    private func startMonitoring() {
        workspace.notificationCenter.addObserver(
            self, selector: #selector(updateRunningApps),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil
        )
        workspace.notificationCenter.addObserver(
            self, selector: #selector(updateRunningApps),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil
        )
        updateRunningApps()
    }

    @objc private func updateRunningApps() {
        let running = workspace.runningApplications
        for i in 0..<availableApps.count {
            availableApps[i].isRunning = running.contains {
                $0.bundleIdentifier == availableApps[i].bundleIdentifier
            }
        }
        runningApps = availableApps.filter { $0.isRunning }
    }
}
```
- Use NSWorkspace to query app installation
- Monitor launch/terminate notifications for runtime tracking
- Publish changes via @Published for UI reactivity

#### TODO 2.4: Implement MediaCommandSender
**File:** `Reflex/Managers/MediaCommandSender.swift`
**Intent:** Execute AppleScript commands to control media apps
**Implementation:**
```swift
class MediaCommandSender {
    func sendCommand(_ command: MediaCommand, to app: MediaApp) -> Bool {
        let script = buildScript(command: command, app: app)
        let result = AppleScriptHelper.execute(script)

        if result.success {
            Logger.shared.info("Sent \(command) to \(app.name)")
            provideFeedback()
            return true
        } else {
            Logger.shared.error("Failed to send \(command) to \(app.name)", error: result.error)
            return false
        }
    }

    private func buildScript(command: MediaCommand, app: MediaApp) -> String {
        let action = command.appleScriptCommand
        return """
        tell application "\(app.appleScriptName)"
            \(action)
        end tell
        """
    }

    private func provideFeedback() {
        // Optional: NSSound.beep() or visual feedback
        NotificationCenter.default.post(name: Notification.Name("commandSent"), object: nil)
    }
}
```
- Build app-specific AppleScript from templates
- Handle execution errors gracefully
- Provide feedback for successful commands

#### TODO 2.5: Implement MediaKeyListener (CRITICAL)
**File:** `Reflex/Managers/MediaKeyListener.swift`
**Intent:** Intercept global media keypresses using CGEvent tap
**Implementation:**
```swift
class MediaKeyListener {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let router: SmartRouter

    init(router: SmartRouter) {
        self.router = router
    }

    func startListening() {
        guard AccessibilityManager.shared.hasPermission else {
            Logger.shared.error("Cannot start listening: no Accessibility permission")
            return
        }

        let eventMask = CGEventMask(1 << CGEventType.systemDefined.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }

                let listener = Unmanaged<MediaKeyListener>.fromOpaque(refcon).takeUnretainedValue()

                // Parse system-defined event for media keys
                let data = event.data
                let keyCode = Int((data >> 16) & 0xFF)
                let keyFlags = Int((data >> 8) & 0xFF)
                let keyDown = (keyFlags & 0xA) == 0xA

                guard keyDown else { return nil }

                let command: MediaCommand? = {
                    switch keyCode {
                    case Constants.MediaKeyCodes.play: return .playPause
                    case Constants.MediaKeyCodes.next: return .nextTrack
                    case Constants.MediaKeyCodes.previous: return .previousTrack
                    case Constants.MediaKeyCodes.volumeUp: return .volumeUp
                    case Constants.MediaKeyCodes.volumeDown: return .volumeDown
                    default: return nil
                    }
                }()

                if let command = command {
                    DispatchQueue.main.async {
                        listener.router.routeCommand(command)
                    }
                    return nil  // Suppress system handling
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Logger.shared.error("Failed to create CGEvent tap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            Logger.shared.info("Media key listener started")
        }
    }

    func stopListening() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        Logger.shared.info("Media key listener stopped")
    }
}
```
**Technical Notes:**
- CGEvent tap requires Accessibility permission
- Event callback must be at module level or use Unmanaged for context
- Return nil to suppress system handling (prevent default media behavior)
- Run on main run loop for reliability
- Monitor tap status and re-enable if disabled by system

#### TODO 2.6: Implement SmartRouter (CRITICAL)
**File:** `Reflex/Managers/SmartRouter.swift`
**Intent:** Intelligent routing logic with auto-switching
**Implementation:**
```swift
class SmartRouter: ObservableObject {
    @Published var activeApp: MediaApp?

    private let appDetector: MediaAppDetector
    private let commandSender: MediaCommandSender
    private let preferences: PreferencesManager
    private let stateManager: PlaybackStateManager
    private var pollingTimer: Timer?

    init(appDetector: MediaAppDetector, commandSender: MediaCommandSender,
         preferences: PreferencesManager, stateManager: PlaybackStateManager) {
        self.appDetector = appDetector
        self.commandSender = commandSender
        self.preferences = preferences
        self.stateManager = stateManager

        if preferences.prefs.autoSwitchEnabled {
            startPolling()
        }
    }

    func routeCommand(_ command: MediaCommand) {
        let target = determineTargetApp()

        guard let app = target else {
            if preferences.prefs.fallbackToSystem {
                // Let system handle it (don't suppress event)
            }
            return
        }

        let success = commandSender.sendCommand(command, to: app)
        if success {
            preferences.setLastUsedApp(app.id)
            activeApp = app
        }
    }

    private func determineTargetApp() -> MediaApp? {
        let prefs = preferences.prefs

        // Priority 1: Auto-switch to currently playing app
        if prefs.autoSwitchEnabled, let playing = findPlayingApp() {
            return playing
        }

        // Priority 2: Last used app (if still running)
        if let lastUsedId = prefs.lastUsedApp,
           let lastApp = appDetector.availableApps.first(where: {
               $0.id == lastUsedId && $0.isRunning
           }) {
            return lastApp
        }

        // Priority 3: First running favorite
        let favorites = appDetector.availableApps.filter {
            prefs.favoriteApps.contains($0.id) && $0.isRunning
        }
        if let first = favorites.first {
            return first
        }

        // Priority 4: Any running media app
        return appDetector.runningApps.first
    }

    private func findPlayingApp() -> MediaApp? {
        for app in appDetector.runningApps {
            if AppleScriptHelper.checkIfAppIsPlaying(app) {
                return app
            }
        }
        return nil
    }

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pollPlaybackState()
        }
    }

    private func pollPlaybackState() {
        if let playing = findPlayingApp() {
            let (track, artist) = AppleScriptHelper.getCurrentTrack(from: playing)
            stateManager.currentState = PlaybackState(
                app: playing, isPlaying: true,
                trackName: track, artistName: artist,
                timestamp: Date()
            )
            stateManager.activeApp = playing
        } else {
            stateManager.currentState = nil
        }
    }
}
```
**Routing Priority:**
1. Currently playing app (auto-switch)
2. Last used app (if still running)
3. First running favorite
4. Any running media app
5. Fallback to system (optional)

---

### Phase 3: User Interface

#### TODO 3.1: Implement StatusBarManager
**File:** `Reflex/Managers/StatusBarManager.swift`
**Intent:** Manage menu bar presence and popover display
**Implementation:**
```swift
class StatusBarManager: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    @Published var currentApp: MediaApp?
    @Published var currentTrack: String?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Reflex")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover?.contentViewController = NSHostingController(rootView: StatusBarView())
        popover?.behavior = .transient
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button else { return }

        if let popover = popover {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    func updateDisplay(app: MediaApp?, track: String?) {
        guard let button = statusItem?.button else { return }

        if let app = app {
            if let track = track {
                button.title = " \(app.name): \(track)"
            } else {
                button.title = " \(app.name)"
            }
        } else {
            button.title = ""
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Reflex")
        }
    }

    func flashIcon() {
        // Visual feedback animation
        guard let button = statusItem?.button else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            button.alphaValue = 0.5
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                button.alphaValue = 1.0
            }
        }
    }
}
```

#### TODO 3.2: Create StatusBarView (Popover)
**File:** `Reflex/UI/StatusBar/StatusBarView.swift`
**Intent:** SwiftUI popover showing current state and quick actions
**Implementation:**
```swift
struct StatusBarView: View {
    @EnvironmentObject var router: SmartRouter
    @EnvironmentObject var appDetector: MediaAppDetector
    @EnvironmentObject var preferences: PreferencesManager
    @EnvironmentObject var stateManager: PlaybackStateManager

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "music.note.circle.fill")
                Text("Reflex").font(.headline)
                Spacer()
            }

            Divider()

            // Now Playing Section
            if let state = stateManager.currentState, state.isPlaying {
                VStack(alignment: .leading) {
                    Text("Now Playing:").font(.caption).foregroundColor(.secondary)
                    Text(state.app?.name ?? "Unknown").font(.headline)
                    if preferences.prefs.showTrackInfo, let track = state.trackName {
                        Text(track).font(.subheadline)
                        if let artist = state.artistName {
                            Text(artist).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                Divider()
            }

            // Quick Switch
            Text("Quick Switch").font(.caption).foregroundColor(.secondary)
            ForEach(favoriteApps) { app in
                AppRowView(app: app, isActive: router.activeApp?.id == app.id) {
                    selectApp(app)
                }
            }

            Divider()

            // Actions
            HStack {
                Button("Preferences...") { openPreferences() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 300)
    }

    private var favoriteApps: [MediaApp] {
        appDetector.availableApps.filter { app in
            preferences.prefs.favoriteApps.contains(app.id) && app.isInstalled
        }
    }

    private func selectApp(_ app: MediaApp) {
        preferences.setLastUsedApp(app.id)
        router.activeApp = app
    }

    private func openPreferences() {
        // Show preferences window
    }
}
```

#### TODO 3.3: Create PreferencesWindow
**File:** `Reflex/UI/Preferences/PreferencesWindow.swift`
**Intent:** Tabbed preferences interface
**Implementation:**
```swift
struct PreferencesWindow: View {
    @State private var selectedTab: PreferenceTab = .general

    enum PreferenceTab: String, CaseIterable {
        case general = "General"
        case apps = "Apps"
        case shortcuts = "Shortcuts"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPreferencesView()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(PreferenceTab.general)
            AppsPreferencesView()
                .tabItem { Label("Apps", systemImage: "music.note.list") }
                .tag(PreferenceTab.apps)
            ShortcutsPreferencesView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(PreferenceTab.shortcuts)
        }
        .frame(width: 500, height: 400)
    }
}
```

#### TODO 3.4: Create GeneralPreferencesView
**File:** `Reflex/UI/Preferences/GeneralPreferencesView.swift`
**Intent:** General app settings (behavior, display, system)
**Implementation:**
```swift
struct GeneralPreferencesView: View {
    @EnvironmentObject var preferences: PreferencesManager

    var body: some View {
        Form {
            Section("Behavior") {
                Toggle("Enable smart auto-switching", isOn: $preferences.prefs.autoSwitchEnabled)
                Toggle("Fallback to system when no app running", isOn: $preferences.prefs.fallbackToSystem)
                Toggle("Enable volume key routing", isOn: $preferences.prefs.enableVolumeKeys)
            }
            Section("Display") {
                Toggle("Show now playing in menu bar", isOn: $preferences.prefs.showNowPlaying)
                Toggle("Show track info", isOn: $preferences.prefs.showTrackInfo)
                    .disabled(!preferences.prefs.showNowPlaying)
            }
            Section("System") {
                Toggle("Launch at login", isOn: $preferences.prefs.launchAtLogin)
                    .onChange(of: preferences.prefs.launchAtLogin) { toggleLaunchAtLogin($0) }
            }
        }
        .padding()
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        }
    }
}
```

#### TODO 3.5: Create AppsPreferencesView
**File:** `Reflex/UI/Preferences/AppsPreferencesView.swift`
**Intent:** Manage favorite apps list
**Implementation:**
```swift
struct AppsPreferencesView: View {
    @EnvironmentObject var appDetector: MediaAppDetector
    @EnvironmentObject var preferences: PreferencesManager

    var body: some View {
        VStack(alignment: .leading) {
            Text("Favorite Apps").font(.headline)
            Text("Select apps to appear in quick switch menu").font(.caption).foregroundColor(.secondary)

            List {
                ForEach(appDetector.availableApps.filter { $0.isInstalled }) { app in
                    HStack {
                        Image(systemName: app.icon ?? "app")
                        Text(app.name)
                        Spacer()
                        Toggle("", isOn: binding(for: app)).labelsHidden()
                    }
                }
            }
        }
        .padding()
    }

    private func binding(for app: MediaApp) -> Binding<Bool> {
        Binding(
            get: { preferences.prefs.favoriteApps.contains(app.id) },
            set: { isOn in
                if isOn {
                    preferences.addFavorite(app.id)
                } else {
                    preferences.removeFavorite(app.id)
                }
            }
        )
    }
}
```

#### TODO 3.6: Create WelcomeView (Onboarding)
**File:** `Reflex/UI/Onboarding/WelcomeView.swift`
**Intent:** First-launch onboarding flow
**Implementation:**
```swift
struct WelcomeView: View {
    @State private var currentStep = 0
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack {
            switch currentStep {
            case 0: WelcomeStepView()
            case 1: PermissionsGuideView()
            case 2: AppSelectionStepView()
            default: CompletionStepView()
            }

            HStack {
                if currentStep > 0 {
                    Button("Back") { currentStep -= 1 }
                }
                Spacer()
                Button(currentStep == 3 ? "Finish" : "Next") {
                    if currentStep == 3 {
                        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                        dismiss()
                    } else {
                        currentStep += 1
                    }
                }
            }
        }
        .frame(width: 600, height: 450)
    }
}
```

#### TODO 3.7: Create PermissionsGuideView
**File:** `Reflex/UI/Onboarding/PermissionsGuideView.swift`
**Intent:** Guide user through Accessibility permission setup
**Implementation:**
```swift
struct PermissionsGuideView: View {
    @StateObject private var accessibilityManager = AccessibilityManager.shared
    @State private var pollingTimer: Timer?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: accessibilityManager.hasPermission ?
                  "checkmark.circle.fill" : "lock.shield")
                .font(.system(size: 60))
                .foregroundColor(accessibilityManager.hasPermission ? .green : .orange)

            Text("Accessibility Permission Required").font(.title).bold()
            Text("Reflex needs Accessibility permission to intercept media keys")
                .multilineTextAlignment(.center)

            VStack(alignment: .leading) {
                InstructionStep(number: 1, text: "Click 'Open System Preferences' below")
                InstructionStep(number: 2, text: "Find Reflex in the list and enable it")
                InstructionStep(number: 3, text: "Return to this window")
            }

            if !accessibilityManager.hasPermission {
                Button("Open System Preferences") {
                    accessibilityManager.openSystemPreferences()
                    startPolling()
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Permission granted!")
                }
            }
        }
    }

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
            accessibilityManager.checkPermission()
            if accessibilityManager.hasPermission {
                timer.invalidate()
            }
        }
    }
}
```

---

### Phase 4: Main App Integration

#### TODO 4.1: Implement ReflexApp Entry Point
**File:** `Reflex/ReflexApp.swift`
**Intent:** Wire up all managers and initialize app lifecycle
**Implementation:**
```swift
import SwiftUI
import Combine

@main
struct ReflexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    // Singletons
    private let accessibilityManager = AccessibilityManager.shared
    private let preferencesManager = PreferencesManager.shared
    private let logger = Logger.shared

    // Initialized managers
    private var appDetector: MediaAppDetector!
    private var commandSender: MediaCommandSender!
    private var stateManager: PlaybackStateManager!
    private var smartRouter: SmartRouter!
    private var mediaKeyListener: MediaKeyListener!
    private var statusBarManager: StatusBarManager!

    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Reflex starting...")

        // Initialize managers in dependency order
        appDetector = MediaAppDetector()
        commandSender = MediaCommandSender()
        stateManager = PlaybackStateManager()
        smartRouter = SmartRouter(
            appDetector: appDetector,
            commandSender: commandSender,
            preferences: preferencesManager,
            stateManager: stateManager
        )
        mediaKeyListener = MediaKeyListener(router: smartRouter)
        statusBarManager = StatusBarManager()

        // Setup UI
        statusBarManager.setup()

        // Check onboarding
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if !hasCompletedOnboarding {
            showOnboarding()
        } else if accessibilityManager.hasPermission {
            mediaKeyListener.startListening()
        } else {
            showPermissionReminder()
        }

        // Observe state changes
        setupObservers()

        logger.info("Reflex ready")
    }

    private func setupObservers() {
        // Update menu bar when playback state changes
        stateManager.$currentState
            .sink { [weak self] state in
                self?.statusBarManager.updateDisplay(app: state?.app, track: state?.trackName)
            }
            .store(in: &cancellables)
    }

    private func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Welcome to Reflex"
        window.center()
        window.contentView = NSHostingView(rootView: WelcomeView())
        window.makeKeyAndOrderFront(nil)
    }

    private func showPermissionReminder() {
        // Show alert or status bar warning
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Keep running when windows closed
    }
}
```

---

### Phase 5: Testing & Polish

#### TODO 5.1: Test Media Key Capture
**Intent:** Verify CGEvent tap captures all media keys correctly
**Testing:**
- Press F7, F8, F9 (previous, play/pause, next)
- Test Fn+Arrow combinations
- Test with different keyboards (internal, external, Bluetooth)
- Verify event suppression (system doesn't also handle)

#### TODO 5.2: Test App Detection & Switching
**Intent:** Verify app discovery and auto-switching works
**Testing:**
- Launch/quit Spotify, Apple Music, VLC
- Verify running state updates in UI
- Test auto-switching when multiple apps playing
- Test manual selection overrides auto-switch

#### TODO 5.3: Test AppleScript Commands
**Intent:** Verify commands work with all supported apps
**Testing:**
- Test play/pause, next, previous with each app
- Test with app in background vs foreground
- Test when app is not running (graceful error)
- Test when app is playing vs paused

#### TODO 5.4: Test Permissions Flow
**Intent:** Verify onboarding and permission requests work
**Testing:**
- Reset onboarding flag and relaunch
- Deny Accessibility permission, verify graceful handling
- Grant permission mid-session, verify app detects it
- Test System Preferences deep link

#### TODO 5.5: Test Preferences Persistence
**Intent:** Verify settings save/load correctly
**Testing:**
- Toggle all preferences, quit, relaunch
- Add/remove favorites, verify persistence
- Test launch at login toggle

#### TODO 5.6: Polish Visual Feedback
**Intent:** Add animations and feedback for better UX
**Implementation:**
- Flash menu bar icon when command sent (0.15s fade)
- Show toast in popover: "Command sent to Spotify"
- Smooth transitions for status bar text updates
- Optional: subtle sound effect on command (user preference)

#### TODO 5.7: Error Handling & Edge Cases
**Intent:** Handle failure scenarios gracefully
**Scenarios to handle:**
- Target app crashes mid-command → fallback to next app
- AppleScript timeout → log, show notification, continue
- CGEvent tap disabled by system → re-enable automatically
- No favorites set → show helpful message in popover
- Multiple apps playing → use most recently active

---

### Phase 6: Distribution Prep

#### TODO 6.1: Create App Icon
**Intent:** Professional branding for the app
**Requirements:**
- 1024x1024 master icon
- Menu bar icon: 22x22 monochrome template
- Music/media theme (waveform, music note, or play button)
- Export all required sizes to AppIcon.appiconset

#### TODO 6.2: Code Signing Setup
**Intent:** Sign app for distribution outside Mac App Store
**Steps:**
1. Obtain Apple Developer ID Application certificate
2. Enable Hardened Runtime in build settings
3. Add entitlements file:
   - `com.apple.security.automation.apple-events`
4. Sign app: `codesign --deep --force --verify --verbose --sign "Developer ID Application" Reflex.app`

#### TODO 6.3: Notarization
**Intent:** Get app notarized by Apple for Gatekeeper
**Steps:**
1. Create DMG: `hdiutil create -volname Reflex -srcfolder Reflex.app -ov -format UDZO Reflex.dmg`
2. Submit: `xcrun notarytool submit Reflex.dmg --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PASSWORD`
3. Staple: `xcrun stapler staple Reflex.dmg`

#### TODO 6.4: Create README & Documentation
**Intent:** User documentation and setup guide
**Contents:**
- What is Reflex and what it does
- Installation instructions
- How to grant Accessibility permission (with screenshots)
- How to add favorite apps
- Troubleshooting common issues
- Privacy statement (what data is collected: none)
- License (MIT recommended)

#### TODO 6.5: Create DMG Installer
**Intent:** Professional installer package
**Implementation:**
- Use `create-dmg` tool or manual DMG creation
- Include: Reflex.app, README.pdf, Applications folder alias
- Background image with drag-to-install instructions
- License agreement (optional)

---

## Technical Architecture Summary

### Data Flow
```
User presses media key
  → CGEvent tap intercepts (MediaKeyListener)
  → Parses key code into MediaCommand
  → Routes to SmartRouter
  → SmartRouter determines target app (auto-switch or manual)
  → MediaCommandSender builds AppleScript
  → Executes AppleScript to control app
  → PlaybackStateManager updates (for UI)
  → StatusBarManager reflects change in menu bar
```

### Dependency Graph
```
ReflexApp (entry point)
  ├── AccessibilityManager (singleton)
  ├── PreferencesManager (singleton)
  ├── Logger (singleton)
  ├── MediaAppDetector
  ├── MediaCommandSender
  │     └── AppleScriptHelper
  ├── PlaybackStateManager
  ├── SmartRouter
  │     ├── MediaAppDetector
  │     ├── MediaCommandSender
  │     ├── PreferencesManager
  │     └── PlaybackStateManager
  ├── MediaKeyListener
  │     ├── SmartRouter
  │     └── AccessibilityManager
  └── StatusBarManager
        └── PlaybackStateManager
```

---

## Critical Implementation Notes

### CGEvent Tap Challenges
- **Requires Accessibility permission** - check before creating tap
- **Can be disabled by system** - monitor and re-enable if needed
- **Must run on main run loop** - don't block the callback
- **Return nil to suppress** - prevents system from also handling key

### AppleScript Quirks
- **Timeout:** Set 3-second timeout for all scripts
- **App-specific syntax:** Some apps use "play" vs "playpause"
- **Error handling:** App not running returns error, catch gracefully
- **Performance:** Compile scripts once if possible (future optimization)

### NSWorkspace Monitoring
- **Launch notifications:** May fire multiple times, deduplicate
- **Bundle ID matching:** Case-sensitive, use exact IDs from JSON
- **Background apps:** Some apps run but don't show in Dock, still detectable

### UserDefaults Persistence
- **Codable for complex types:** Encode/decode AppPreferences as JSON
- **Observe changes:** Use @Published with didSet for auto-save
- **Migration:** Consider version number for future schema changes

---

## Files Summary (Base Path: `/Users/oluwaseunus/Documents/Work/reflex/Reflex/`)

### Critical Files (Implement First)
1. `Models/MediaApp.swift`
2. `Models/MediaCommand.swift`
3. `Utilities/AppleScriptHelper.swift`
4. `Managers/MediaCommandSender.swift`
5. `Managers/MediaKeyListener.swift`
6. `Managers/SmartRouter.swift`

### Supporting Files
- `Models/PlaybackState.swift`
- `Models/AppPreferences.swift`
- `Utilities/Logger.swift`
- `Utilities/Constants.swift`
- `Managers/AccessibilityManager.swift`
- `Managers/PreferencesManager.swift`
- `Managers/MediaAppDetector.swift`
- `Managers/StatusBarManager.swift`

### UI Files
- `UI/StatusBar/StatusBarView.swift`
- `UI/Preferences/PreferencesWindow.swift`
- `UI/Preferences/GeneralPreferencesView.swift`
- `UI/Preferences/AppsPreferencesView.swift`
- `UI/Onboarding/WelcomeView.swift`
- `UI/Onboarding/PermissionsGuideView.swift`

### Configuration
- `Info.plist`
- `Resources/MediaAppDefinitions.json`
- `ReflexApp.swift` (entry point)

---

## Implementation Timeline Estimate

**Phase 0-1:** Foundation (Models, Utilities) - 2-3 days
**Phase 2:** Core Managers - 3-4 days
**Phase 3:** User Interface - 2-3 days
**Phase 4:** Integration & Wiring - 1 day
**Phase 5:** Testing & Polish - 2-3 days
**Phase 6:** Distribution - 1 day

**Total:** ~11-15 days of development time

---

## Next Steps

1. Create Xcode project
2. Implement Phase 1 (Models & Utilities)
3. Implement Phase 2 (Core Managers)
4. Test core functionality in isolation
5. Build UI layer
6. Integration testing with real apps
7. Polish and distribute

**Ready to begin implementation!**
