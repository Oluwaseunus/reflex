import SwiftUI
import ServiceManagement

/// General preferences tab
struct GeneralPreferencesView: View {
    @EnvironmentObject var preferences: PreferencesManager
    @ObservedObject var accessibilityManager = AccessibilityManager.shared

    var body: some View {
        Form {
            // Behavior Section
            Section {
                Toggle("Enable smart auto-switching", isOn: $preferences.prefs.autoSwitchEnabled)
                    .help("Automatically route to whichever app is currently playing")

                Toggle("Fall back to system when no media app is playing",
                       isOn: $preferences.prefs.fallbackToSystem)
                    .help("Let system handle media keys when no registered media app is actively playing")

                Toggle("Route volume keys through Reflex",
                       isOn: $preferences.prefs.enableVolumeKeys)
                    .help("Control volume of target app instead of system volume")

                Toggle("Return focus to previous app when closing popover",
                       isOn: $preferences.prefs.restoreFocusOnClose)
                    .help("Restore focus to the app you were using when the popover is dismissed from the menu bar")
            } header: {
                Text("Behavior")
            }

            // Display Section
            Section {
                Toggle("Show now playing in menu bar",
                       isOn: $preferences.prefs.showNowPlaying)
                    .help("Display the active app name in the menu bar")

                Toggle("Show track info",
                       isOn: $preferences.prefs.showTrackInfo)
                    .disabled(!preferences.prefs.showNowPlaying)
                    .help("Display current track name in the menu bar")

                Toggle("Include artist name",
                       isOn: $preferences.prefs.showArtistInMenuBar)
                    .disabled(!preferences.prefs.showNowPlaying || !preferences.prefs.showTrackInfo)
                    .help("Show \"song - artist\" in the menu bar when available")
            } header: {
                Text("Display")
            }

            // Feedback Section
            Section {
                Toggle("Show visual feedback",
                       isOn: $preferences.prefs.showVisualFeedback)
                    .help("Flash menu bar icon when commands are sent")

                Toggle("Play audio feedback",
                       isOn: $preferences.prefs.playAudioFeedback)
                    .help("Play a sound when commands are sent")
            } header: {
                Text("Feedback")
            }

            // System Section
            Section {
                Toggle("Launch at login", isOn: $preferences.prefs.launchAtLogin)
                    .onChange(of: preferences.prefs.launchAtLogin) { newValue in
                        toggleLaunchAtLogin(newValue)
                    }
                    .help("Start Reflex automatically when you log in")

                HStack {
                    Text("Polling interval")
                    Spacer()
                    Picker("", selection: $preferences.prefs.pollingInterval) {
                        Text("3 seconds").tag(3.0 as TimeInterval)
                        Text("5 seconds").tag(5.0 as TimeInterval)
                        Text("10 seconds").tag(10.0 as TimeInterval)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                .help("How often to check for playback state changes")
            } header: {
                Text("System")
            }

            // Permissions Section
            Section {
                HStack {
                    Image(systemName: accessibilityManager.hasPermission ?
                          "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(accessibilityManager.hasPermission ? .green : .red)

                    Text("Accessibility Permission")

                    Spacer()

                    if accessibilityManager.hasPermission {
                        Text("Granted")
                            .foregroundColor(.secondary)
                    } else {
                        Button("Grant Access") {
                            accessibilityManager.openSystemPreferences()
                        }
                    }
                }
            } header: {
                Text("Permissions")
            }
        }
        .modifier(GroupedFormStyleModifier())
        .padding()
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                Logger.shared.info("Launch at login \(enabled ? "enabled" : "disabled")")
            } catch {
                Logger.shared.error("Failed to toggle launch at login", error: error)
            }
        } else {
            // Fallback for older macOS
            Logger.shared.warning("Launch at login requires macOS 13+")
        }
    }
}

/// Modifier to apply grouped form style on macOS 13+ only
struct GroupedFormStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.formStyle(.grouped)
        } else {
            content
        }
    }
}

#if DEBUG
struct GeneralPreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralPreferencesView()
            .environmentObject(PreferencesManager.shared)
            .frame(width: 500, height: 400)
    }
}
#endif
