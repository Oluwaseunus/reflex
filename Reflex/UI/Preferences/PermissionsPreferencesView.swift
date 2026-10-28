import SwiftUI
import AppKit

/// Permissions preferences tab
struct PermissionsPreferencesView: View {
    var body: some View {
        Form {
            Section {
                AutomationPermissionControls()
            } header: {
                Text("Automation")
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

#if DEBUG
struct PermissionsPreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PermissionsPreferencesView()
            .environmentObject(PreferencesManager.shared)
            .frame(width: 520, height: 420)
    }
}
#endif
