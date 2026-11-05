import SwiftUI
import AppKit
import MusicKit

/// Permissions preferences tab
struct PermissionsPreferencesView: View {
    var body: some View {
        Form {
            Section {
                MusicKitPermissionControls()
            } header: {
                Text("Apple Music")
            }
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
    @EnvironmentObject private var preferences: PreferencesManager
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
                    Text("Allow Reflex to control \(preferences.playbackPlayer.name)")
                    Text("Reflex uses macOS Automation to control \(preferences.playbackPlayer.name) and read the current track.")
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
        .onChange(of: preferences.playbackPlayer) { _, _ in
            statusMessage = nil
        }
    }

    private func requestAutomationAccess() {
        let result = AppleScriptHelper.requestAutomationPermission(for: preferences.playbackPlayer)
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

struct MusicKitPermissionControls: View {
    @State private var authorization = MusicAuthorization.currentStatus
    @State private var isConnecting = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect Apple Music")
                .font(.headline)
            Text("Resolve the current song’s catalog links, album and artists through MusicKit.")
                .font(.caption)
                .foregroundColor(.secondary)
            Button(authorization == .authorized ? "Check Connection" : "Connect Apple Music") {
                connect()
            }
            .disabled(isConnecting)
            if isConnecting { ProgressView().controlSize(.small) }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(isError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { authorization = MusicAuthorization.currentStatus }
    }

    private func connect() {
        isConnecting = true
        message = nil
        Task { @MainActor in
            defer { isConnecting = false }
            authorization = await MusicAuthorization.request()
            guard authorization == .authorized else {
                isError = true
                message = AppleMusicCatalogError.denied.localizedDescription
                return
            }
            do {
                var request = MusicCatalogChartsRequest(types: [Song.self])
                request.limit = 1
                _ = try await request.response()
                isError = false
                message = "Apple Music is connected."
                NotificationCenter.default.post(name: .musicAuthorizationChanged, object: nil)
            } catch {
                isError = true
                message = "Apple Music connection failed: \(error.localizedDescription)"
            }
        }
    }
}
