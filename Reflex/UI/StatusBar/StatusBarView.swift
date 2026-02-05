import SwiftUI
import Combine

/// Main popover view shown when clicking the status bar icon
struct StatusBarView: View {
    @EnvironmentObject var stateManager: PlaybackStateManager
    @EnvironmentObject var preferences: PreferencesManager
    @EnvironmentObject var router: SmartRouter
    @EnvironmentObject var appDetector: MediaAppDetector

    @State private var showingPreferences = false

    var body: some View {
        VStack(spacing: 0) {
            if let state = stateManager.currentState, state.isPlaying {
                NowPlayingCard(state: state, router: router, stateManager: stateManager)
            } else {
                headerSection
                    .padding()
            }

            Divider()

            quickSwitchSection
                .padding()

            Divider()

            actionsSection
        }
        .frame(width: 320)
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
        VStack(spacing: 0) {
            Button(action: {
                NotificationCenter.default.post(name: Notification.Name("openPreferences"), object: nil)
            }) {
                HStack {
                    Image(systemName: "gear")
                        .font(.system(size: 11))
                    Text("Preferences...")
                        .font(.system(size: 13))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
            .focusable(false)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                HStack {
                    Image(systemName: "power")
                        .font(.system(size: 11))
                    Text("Quit")
                        .font(.system(size: 13))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .focusable(false)
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
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

/// Modern Now Playing card with album art, controls, and progress
struct NowPlayingCard: View {
    let state: PlaybackState
    let router: SmartRouter
    let stateManager: PlaybackStateManager

    @State private var currentPosition: Double = 0
    @State private var duration: Double = 0
    @State private var albumArtwork: NSImage?
    @State private var isPlaying: Bool = true
    @State private var lastTrackId: String?
    @State private var timerCancellable: AnyCancellable?

    var body: some View {
        VStack(spacing: 0) {
            // App indicator and volume
            HStack {
                Text("• \(state.app?.name.uppercased() ?? "UNKNOWN") •")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 12)

            // Main content: Album art and controls
            HStack(spacing: 12) {
                // Album artwork
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 120, height: 120)

                    if let artwork = albumArtwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                    }
                }
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)

                // Right side: Track info, controls, and progress
                VStack(alignment: .leading, spacing: 0) {
                    // Track name
                    Text(state.trackName ?? "Unknown Track")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Artist and album
                    Text(artistAlbumText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.top, 2)

                    Spacer()

                    // Playback controls
                    HStack(spacing: 0) {
                        Spacer(minLength: 4)

                        Button(action: { sendCommand(.previousTrack) }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)

                        Spacer(minLength: 16)

                        Button(action: { sendCommand(.playPause) }) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)

                        Spacer(minLength: 16)

                        Button(action: { sendCommand(.nextTrack) }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)

                        Spacer(minLength: 4)
                    }
                    .padding(.vertical, 6)

                    Spacer()

                    // Progress bar
                    VStack(spacing: 4) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background track
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(nsColor: .separatorColor))
                                    .frame(height: 3)

                                // Progress
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.primary)
                                    .frame(width: progressWidth(totalWidth: geometry.size.width), height: 3)
                            }
                        }
                        .frame(height: 3)

                        // Time labels
                        HStack {
                            Text(formatTime(currentPosition))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(formatTime(duration))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(height: 120)
            }
        }
        .padding(14)
        .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
        .onAppear {
            isPlaying = state.isPlaying
            loadPlaybackInfo()
            timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    // Reconcile isPlaying with actual state
                    if let currentState = stateManager.currentState {
                        isPlaying = currentState.isPlaying
                    }
                    if isPlaying && currentPosition < duration {
                        currentPosition += 1
                    }
                    loadPlaybackInfo()
                }
        }
        .onDisappear {
            timerCancellable?.cancel()
            timerCancellable = nil
        }
    }

    private var artistAlbumText: String {
        let artist = state.artistName ?? "Unknown Artist"
        if let album = state.albumName {
            return "\(artist) – \(album)"
        }
        return artist
    }

    private func progressWidth(totalWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return totalWidth * CGFloat(currentPosition / duration)
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func sendCommand(_ command: MediaCommand) {
        if command == .playPause {
            isPlaying.toggle()
        }
        router.routeCommand(command)
    }

    private func loadPlaybackInfo() {
        guard let app = state.app else { return }

        // Always fetch position (lightweight local AppleScript)
        if let position = AppleScriptHelper.getPlaybackPosition(from: app) {
            self.currentPosition = position
        }

        // Only fetch artwork and duration on track change
        let trackId = "\(state.trackName ?? "")||\(state.artistName ?? "")"
        guard trackId != lastTrackId else { return }
        lastTrackId = trackId

        if let dur = AppleScriptHelper.getTrackDuration(from: app) {
            self.duration = dur
        }

        Task {
            if let image = await AppleScriptHelper.getArtwork(from: app) {
                await MainActor.run {
                    self.albumArtwork = image
                }
            }
        }
    }
}

/// SwiftUI wrapper for NSVisualEffectView to get the liquid glass blur effect
struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
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
