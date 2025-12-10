import SwiftUI

/// Main popover view shown when clicking the status bar icon
struct StatusBarView: View {
    @EnvironmentObject var stateManager: PlaybackStateManager
    @EnvironmentObject var preferences: PreferencesManager
    @EnvironmentObject var router: SmartRouter
    @EnvironmentObject var appDetector: MediaAppDetector

    @State private var showingPreferences = false

    var body: some View {
        VStack(spacing: 12) {
            // Header
            headerSection

            Divider()

            // Now Playing Section
            if let state = stateManager.currentState, state.isPlaying {
                nowPlayingSection(state: state)
                Divider()
            }

            // Quick Switch Section
            quickSwitchSection

            Divider()

            // Actions
            actionsSection
        }
        .padding()
        .frame(width: 300)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "music.note.circle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            Text("Reflex")
                .font(.headline)
            Spacer()

            // Permission indicator
            if !AccessibilityManager.shared.hasPermission {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .help("Accessibility permission required")
            }
        }
    }

    // MARK: - Now Playing Section

    private func nowPlayingSection(state: PlaybackState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Now Playing")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                if let app = state.app {
                    Image(systemName: app.icon ?? "music.note")
                        .foregroundColor(.accentColor)
                    Text(app.name)
                        .font(.headline)
                }
                Spacer()

                // Playing indicator
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }

            if preferences.prefs.showTrackInfo {
                if let track = state.trackName {
                    Text(track)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                if let artist = state.artistName {
                    Text(artist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Quick Switch Section

    private var quickSwitchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Switch")
                .font(.caption)
                .foregroundColor(.secondary)

            if favoriteApps.isEmpty && appDetector.runningApps.isEmpty {
                Text("No media apps running")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(appsToShow) { app in
                    AppRowView(
                        app: app,
                        isActive: router.activeApp?.id == app.id,
                        onSelect: { router.selectApp(app) }
                    )
                }
            }
        }
    }

    private var favoriteApps: [MediaApp] {
        appDetector.availableApps.filter { app in
            preferences.prefs.favoriteApps.contains(app.id) && app.isInstalled
        }
    }

    private var appsToShow: [MediaApp] {
        // Show favorites first, then other running apps
        let favorites = favoriteApps.filter { $0.isRunning }
        let otherRunning = appDetector.runningApps.filter { app in
            !favorites.contains { $0.id == app.id }
        }
        return favorites + otherRunning
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        HStack {
            Button("Preferences...") {
                NotificationCenter.default.post(name: Notification.Name("openPreferences"), object: nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .font(.caption)
    }
}

/// Row view for a single app in the quick switch list
struct AppRowView: View {
    let app: MediaApp
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: app.icon ?? "app")
                    .frame(width: 20)
                    .foregroundColor(isActive ? .accentColor : .primary)

                Text(app.name)
                    .foregroundColor(isActive ? .accentColor : .primary)

                Spacer()

                if !app.isRunning {
                    Text("Not Running")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!app.isRunning)
        .opacity(app.isRunning ? 1.0 : 0.5)
    }
}

#if DEBUG
struct StatusBarView_Previews: PreviewProvider {
    static var previews: some View {
        StatusBarView()
            .environmentObject(PlaybackStateManager())
            .environmentObject(PreferencesManager.shared)
            .environmentObject(SmartRouter(
                appDetector: MediaAppDetector(),
                commandSender: MediaCommandSender(),
                preferences: PreferencesManager.shared,
                stateManager: PlaybackStateManager()
            ))
            .environmentObject(MediaAppDetector())
    }
}
#endif
