import SwiftUI
import AppKit

/// Permissions preferences tab
struct PermissionsPreferencesView: View {
    @ObservedObject var spotifyAuth = SpotifyAuthManager.shared

    var body: some View {
        Form {
            Section {
                AutomationPermissionControls()
            } header: {
                Text("Automation")
            }

            Section {
                SpotifyAccountControls(spotifyAuth: spotifyAuth)
            } header: {
                Text("Spotify Account")
            }
        }
        .modifier(GroupedFormStyleModifier())
        .padding()
    }
}

struct AutomationPermissionControls: View {
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Allow Reflex to control Spotify")
                    Text("Reflex uses macOS Automation to control Spotify and read the current track and context.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack {
                Button("Request Access") {
                    requestAutomationAccess()
                }

                Button("Open Settings") {
                    openAutomationSettings()
                }

                Spacer()
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(statusIsError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func requestAutomationAccess() {
        let result = AppleScriptHelper.requestSpotifyAutomationPermission()
        statusIsError = !result.success
        statusMessage = result.success
            ? "Automation access is available, or macOS recorded your choice."
            : result.error?.localizedDescription ?? "Could not request Automation access."
    }

    private func openAutomationSettings() {
        guard let url = URL(string: Constants.URLs.automationPreferences) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct SpotifyAccountControls: View {
    @ObservedObject var spotifyAuth: SpotifyAuthManager

    var body: some View {
        HStack {
            Image(systemName: spotifyAuth.isSignedIn ? "checkmark.circle.fill" : "circle")
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
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = spotifyAuth.lastErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
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
    }
}

#if DEBUG
struct PermissionsPreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PermissionsPreferencesView()
            .environmentObject(PreferencesManager.shared)
            .frame(width: 520, height: 420)
    }
}
#endif
