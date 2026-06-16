import SwiftUI
import ServiceManagement

/// General preferences tab
struct GeneralPreferencesView: View {
    @EnvironmentObject var preferences: PreferencesManager
    @ObservedObject var spotifyAuth = SpotifyAuthManager.shared

    var body: some View {
        Form {
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

                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Update menu bar while popover is open",
                           isOn: $preferences.prefs.updateMenuBarWhilePopoverOpen)
                        .disabled(!preferences.prefs.showNowPlaying || !preferences.prefs.showTrackInfo)
                        .help("Allow the menu bar title to change while the popover is visible")
                    Text("Enabling this may cause the popover to shift position when switching tracks.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Search highlight color")
                    Spacer()
                    Picker("", selection: $preferences.prefs.searchHighlightStyle) {
                        Text("Accent").tag(SearchHighlightStyle.accent)
                        Text("Neutral").tag(SearchHighlightStyle.neutral)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                .help("Color used to highlight the selected row in the Spotify search popup")
            } header: {
                Text("Display")
            }

            // System Section
            Section {
                Toggle("Launch at login", isOn: $preferences.prefs.launchAtLogin)
                    .onChange(of: preferences.prefs.launchAtLogin) { _, newValue in
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

            // Spotify Account Section
            Section {
                HStack {
                    Image(systemName: spotifyAuth.isSignedIn ?
                          "checkmark.circle.fill" : "circle")
                        .foregroundColor(spotifyAuth.isSignedIn ? .green : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        if !spotifyAuth.isConfigured {
                            Text("Unavailable in this build")
                            Text("This build was compiled without Spotify API credentials.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(spotifyAuth.isSignedIn ? "Connected" : "Not connected")
                            Text("Sign in to search Spotify, play tracks and albums, and queue tracks.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let error = spotifyAuth.lastErrorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    Spacer()

                    if spotifyAuth.isSignedIn {
                        Button("Disconnect") { spotifyAuth.signOut() }
                    } else {
                        Button("Connect Spotify") { spotifyAuth.beginSignIn() }
                            .disabled(!spotifyAuth.isConfigured)
                    }
                }
            } header: {
                Text("Spotify Account")
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
