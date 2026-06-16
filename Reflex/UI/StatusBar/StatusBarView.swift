import SwiftUI
import Combine
import AppKit

/// Main popover view shown when clicking the status bar icon
struct StatusBarView: View {
    @EnvironmentObject var stateManager: PlaybackStateManager
    @EnvironmentObject var preferences: PreferencesManager
    @EnvironmentObject var router: SmartRouter
    @ObservedObject private var spotifyAuth = SpotifyAuthManager.shared

    @State private var showingPreferences = false
    @State private var queueExpanded = false
    @State private var queueTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if let state = stateManager.currentState {
                NowPlayingCard(state: state, router: router, stateManager: stateManager)
            } else {
                headerSection
                    .padding()
            }

            Divider()

            actionsSection
        }
        .frame(width: 320)
        .onAppear {
            refreshSpotifyQueue()
        }
        .onDisappear {
            queueTask?.cancel()
        }
        .onChange(of: stateManager.currentState?.trackKey) { _, _ in
            refreshSpotifyQueue(force: true)
        }
        .onChange(of: spotifyAuth.isSignedIn) { _, signedIn in
            if signedIn {
                refreshSpotifyQueue(force: true)
            } else {
                queueExpanded = false
                stateManager.updateSpotifyQueue([])
            }
        }
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
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 0) {
            queueActionSection

            Divider()

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

    private var queueActionSection: some View {
        VStack(spacing: 0) {
            Button(action: toggleQueue) {
                HStack {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 11))
                    Text(queueExpanded ? "Hide Queue" : "Show Queue")
                        .font(.system(size: 13))
                    Spacer()
                    if stateManager.isSpotifyQueueLoading {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.55)
                            .frame(width: 14, height: 14)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(queueButtonDisabled ? .secondary : .primary)
            .focusable(false)
            .disabled(queueButtonDisabled)
            .help(queueHelpText)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if queueExpanded {
                queueItemsSection
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var queueItemsSection: some View {
        if stateManager.isSpotifyQueueLoading &&
            stateManager.spotifyQueueItems.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.65)
                Text("Loading Queue")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(stateManager.spotifyQueueItems.prefix(5).enumerated()), id: \.offset) { _, item in
                    QueueItemRow(item: item, onOpenSpotify: openSpotifyApp)
                }
            }
        }
    }

    private var queueButtonDisabled: Bool {
        if !spotifyAuth.isSignedIn { return true }
        if stateManager.isSpotifyQueueLoading { return false }
        return stateManager.spotifyQueueItems.isEmpty
    }

    private var queueHelpText: String {
        if !spotifyAuth.isSignedIn {
            return "Connect Spotify to show queue"
        }
        if let error = stateManager.spotifyQueueError {
            return error
        }
        if stateManager.spotifyQueueItems.isEmpty {
            return "No items in queue"
        }
        return queueExpanded ? "Hide queue" : "Show queue"
    }

    private func toggleQueue() {
        if queueExpanded {
            queueExpanded = false
        } else {
            queueExpanded = true
            refreshSpotifyQueue(force: true)
        }
    }

    private func refreshSpotifyQueue(force: Bool = false) {
        guard spotifyAuth.isSignedIn else {
            stateManager.updateSpotifyQueue([])
            return
        }
        if !force,
           let lastUpdate = stateManager.spotifyQueueLastUpdate,
           Date().timeIntervalSince(lastUpdate) < 8 {
            return
        }

        queueTask?.cancel()
        stateManager.setSpotifyQueueLoading()
        queueTask = Task {
            do {
                let items = try await SpotifyUserAPI.shared.currentQueue(limit: 5)
                if Task.isCancelled { return }
                await MainActor.run {
                    stateManager.updateSpotifyQueue(items)
                    if items.isEmpty {
                        queueExpanded = false
                    }
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    stateManager.updateSpotifyQueue([], error: queueErrorMessage(error))
                    queueExpanded = false
                }
            }
        }
    }

    private func queueErrorMessage(_ error: Error) -> String {
        switch error {
        case SpotifyUserAPIError.notSignedIn:
            return "Connect Spotify to show queue"
        case SpotifyUserAPIError.keychain:
            return "Connect Spotify again to show queue"
        case SpotifyUserAPIError.rateLimited:
            return "Spotify is rate limiting queue updates"
        case SpotifyUserAPIError.network:
            return "Could not load Spotify queue"
        case SpotifyUserAPIError.httpStatus(403, _):
            return "Reconnect Spotify to grant queue access"
        default:
            return "Could not load Spotify queue"
        }
    }

    private func openSpotifyApp() {
        let bundleID = "com.spotify.client"
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
            return
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
            app?.activate()
        }
    }
}

private struct QueueItemRow: View {
    let item: SpotifyQueueItem
    var onOpenSpotify: () -> Void

    var body: some View {
        Button(action: onOpenSpotify) {
            HStack(spacing: 10) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(item.artistName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Open Spotify")
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = item.artworkURL {
            CachedArtworkImage(url: url) {
                Color.secondary.opacity(0.2)
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 34, height: 34)
        }
    }
}

/// Modern Now Playing card with album art, controls, and progress
struct NowPlayingCard: View {
    /// When the ⏮ button is clicked, positions strictly less than this
    /// threshold (in seconds) go to the previous track; positions at or
    /// above it restart the current track. Matches Spotify's native UI
    /// behavior for the ⏮ button.
    private static let restartThresholdSeconds: Double = 3.0

    let state: PlaybackState
    let router: SmartRouter
    let stateManager: PlaybackStateManager

    @State private var currentPosition: Double = 0
    @State private var duration: Double = 0
    @State private var isPlaying: Bool = true
    @State private var isMuted: Bool = false
    @State private var currentVolume: Int = 50
    @State private var lastTrackId: String?
    @State private var timerCancellable: AnyCancellable?
    @State private var isHoveringProgress: Bool = false
    @State private var isScrubbing: Bool = false
    @State private var scrubPosition: Double = 0
    @State private var isHoveringVolume: Bool = false
    @State private var isScrubbingVolume: Bool = false
    @State private var scrubVolume: Double = 0
    @State private var volumeHideWorkItem: DispatchWorkItem?
    @State private var lastVolumeSendAt: Date = .distantPast
    @State private var lastVolumeSent: Int = -1
    @State private var lastPositionSendAt: Date = .distantPast
    @State private var spotifyTrackStartupGraceUntil: Date = .distantPast

    private let scrubThrottle: TimeInterval = 0.03
    private let spotifyTrackStartupGracePeriod: TimeInterval = 2.0

    var body: some View {
        VStack(spacing: 0) {
            // App indicator and volume
            HStack {
                Text("• \(state.app?.name.uppercased() ?? "UNKNOWN") •")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
                HStack(spacing: 10) {
                    if isSpotify {
                        volumeScrubber
                            .frame(width: showVolumeScrubber ? 100 : 0)
                            .opacity(showVolumeScrubber ? 1 : 0)
                            .animation(.easeInOut(duration: 0.15), value: showVolumeScrubber)
                    }
                    Button(action: toggleMute) {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 14, height: 14, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .foregroundColor(.secondary)
                    .help(isMuted ? "Unmute Spotify" : "Mute Spotify")
                }
                .onHover { hovering in
                    scheduleVolumeVisibility(hovering)
                }

                if !state.isPlaying {
                    Button(action: { stateManager.dismissCurrentTrack() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 14, height: 14, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .foregroundColor(.secondary)
                    .help("Dismiss from menu bar")
                }
            }
            .padding(.bottom, 12)

            // Main content: Album art and controls
            HStack(spacing: 12) {
                // Album artwork
                Button(action: openTrackLink) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(width: 120, height: 120)

                        if let artwork = stateManager.currentArtwork {
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
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(!canOpenTrack)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)

                // Right side: Track info, controls, and progress
                VStack(alignment: .leading, spacing: 0) {
                    // Track name with hover marquee
                    Button(action: openTrackLink) {
                        HoverMarquee(text: state.trackName ?? "Unknown Track")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 18, alignment: .leading)
                            .accessibilityLabel(state.trackName ?? "Unknown Track")
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled(!canOpenTrack)

                    // Artist and album deep links
                    HStack(spacing: 4) {
                        Button(action: openArtistLink) {
                            Text(state.artistName ?? "Unknown Artist")
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .foregroundColor(.secondary)
                        .disabled(!canOpenArtist)

                        if state.albumName != nil {
                            Text("-")
                                .foregroundColor(.secondary)

                            Button(action: openTrackLink) {
                                Text(state.albumName ?? "")
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .focusable(false)
                            .foregroundColor(.secondary)
                            .disabled(!canOpenTrack)
                        }
                    }
                    .font(.system(size: 11))
                    .padding(.top, 2)

                    Spacer()

                    // Playback controls
                    HStack(spacing: 0) {
                        Spacer(minLength: 4)

                        Button(action: replayCurrentTrack) {
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
                            let totalWidth = geometry.size.width
                            let displayPosition = isScrubbing ? scrubPosition : currentPosition
                            let fillWidth = progressWidth(for: displayPosition, totalWidth: totalWidth)

                            ZStack(alignment: .leading) {
                                // Background track
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(nsColor: .separatorColor))
                                    .frame(height: 3)

                                // Progress fill
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.primary)
                                    .frame(width: fillWidth, height: 3)

                                // Scrub handle
                                Circle()
                                    .fill(Color.primary)
                                    .frame(width: 10, height: 10)
                                    .offset(x: max(0, min(fillWidth - 5, totalWidth - 10)))
                                    .opacity(isHoveringProgress || isScrubbing ? 1 : 0)
                            }
                            .frame(height: 10)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                isHoveringProgress = hovering
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard duration > 0 else { return }
                                        isScrubbing = true
                                        let fraction = max(0, min(1, value.location.x / totalWidth))
                                        scrubPosition = Double(fraction) * duration
                                        // Live seek is Spotify-only: non-Spotify apps go through
                                        // AppleScript, which is too slow for per-frame writes.
                                        if isSpotify {
                                            sendPositionThrottled(scrubPosition)
                                        }
                                    }
                                    .onEnded { value in
                                        guard duration > 0, let app = state.app else {
                                            isScrubbing = false
                                            return
                                        }
                                        let fraction = max(0, min(1, value.location.x / totalWidth))
                                        let seekTo = Double(fraction) * duration
                                        currentPosition = seekTo
                                        if isSpotify {
                                            SpotifyBridge.setPlaybackPosition(seekTo)
                                        } else {
                                            AppleScriptHelper.setPlaybackPosition(seekTo, for: app)
                                        }
                                        isScrubbing = false
                                    }
                            )
                        }
                        .frame(height: 10)
                        .padding(.horizontal, 4)
                        .layoutPriority(1)

                        // Time labels
                        HStack {
                            Text(formatTime(isScrubbing ? scrubPosition : currentPosition))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(minWidth: 46, alignment: .leading)
                            Spacer()
                            Text(formatTime(duration))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(minWidth: 46, alignment: .trailing)
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
                loadVolumeInfo()
                loadPlaybackInfo()
                timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
                    .autoconnect()
                    .sink { _ in
                        // Keep muted state in sync if external change
                        syncVolumeState()
                        if isPlaying && currentPosition < duration {
                            currentPosition += 1
                        }
                        loadPlaybackInfo()
                    }
            }
            .onChange(of: state.isPlaying) { _, newValue in
                // Only adopt external state changes; avoids reverting our
                // optimistic toggle while stateManager hasn't repolled yet.
                isPlaying = newValue
            }
            .onReceive(NotificationCenter.default.publisher(for: Constants.Notifications.spotifyPlaybackStartDispatched)) { _ in
                spotifyTrackStartupGraceUntil = Date().addingTimeInterval(SpotifyPlaybackStartupGuard.quietPeriod)
            }
        .onDisappear {
            timerCancellable?.cancel()
            timerCancellable = nil
        }
    }

    private var canOpenAlbum: Bool {
        state.albumName != nil && state.app?.bundleIdentifier == "com.spotify.client"
    }

    private var canOpenTrack: Bool {
        state.trackName != nil && state.app?.bundleIdentifier == "com.spotify.client"
    }

    private var canOpenArtist: Bool {
        state.artistName != nil && state.app?.bundleIdentifier == "com.spotify.client"
    }

    private func openTrackLink() {
        guard canOpenTrack, let app = state.app else { return }
        // Spotify is already on the current track — just bring it to the front.
        // (Opening a spotify:track: URI would auto-play, which we don't want.)
        AppleScriptHelper.activateApp(app)
    }

    private func openAlbumLink() {
        guard canOpenAlbum, let album = state.albumName else { return }
        let uri = AppleScriptHelper.spotifyAlbumSearchURI(album: album, artist: state.artistName)
        AppleScriptHelper.openSpotifyURI(uri)
    }

    private func openArtistLink() {
        guard canOpenArtist, let artist = state.artistName else { return }
        let uri = AppleScriptHelper.spotifyArtistSearchURI(artist: artist)
        AppleScriptHelper.openSpotifyURI(uri)
    }

    private func progressWidth(for position: Double, totalWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return totalWidth * CGFloat(position / duration)
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

    /// Popover ⏮ button action, matching Spotify's native ⏮ behavior with
    /// one deliberate extension: clicks while paused always resume playback.
    ///
    /// - Position ≥ restartThresholdSeconds → seek to 0 on the current track.
    ///   Playing: stays playing. Paused: also resumes (fused seek+play in one
    ///   AppleScript `tell` block).
    /// - Position <  restartThresholdSeconds → go to the previous track.
    ///   Playing: standard `previous track` via the normal routing path.
    ///   Paused: `previous track` + `play` fused in one `tell` block, so the
    ///   previous track auto-plays (matching Spotify's own paused-⏮ UX).
    private func replayCurrentTrack() {
        let wasPaused = !isPlaying
        let goToPrevious = currentPosition < Self.restartThresholdSeconds

        if wasPaused {
            // Optimistic UI update so the icon flips to "pause" immediately.
            // The state manager will repoll and reconcile shortly.
            isPlaying = true
        }

        if goToPrevious {
            if wasPaused {
                router.skipToPreviousSpotifyTrackAndPlay()
            } else {
                router.routeCommand(.previousTrack)
            }
            // currentPosition will be refreshed from Spotify by loadPlaybackInfo
            // on the next timer tick; no optimistic reset here because the
            // track is changing and duration is about to change too.
        } else {
            currentPosition = 0
            router.replayCurrentSpotifyTrack(resumePlayback: wasPaused)
        }
    }

    private func toggleMute() {
        if let muted = router.toggleSpotifyMute() {
            isMuted = muted
            if !muted, let volume = AppleScriptHelper.getVolume(for: state.app!) {
                currentVolume = volume
            }
        }
    }

    private func loadVolumeInfo() {
        guard let app = state.app else { return }
        if isSpotify && SpotifyPlaybackStartupGuard.isSuppressingReads { return }
        if let vol = AppleScriptHelper.getVolume(for: app) {
            currentVolume = vol
            isMuted = vol == 0
        }
    }

    private func syncVolumeState() {
        guard let app = state.app else { return }
        guard !isScrubbingVolume else { return }
        if isSpotify && SpotifyPlaybackStartupGuard.isSuppressingReads { return }
        if let vol = AppleScriptHelper.getVolume(for: app) {
            isMuted = vol == 0
            if vol > 0 { currentVolume = vol }
        }
    }

    private var showVolumeScrubber: Bool {
        isSpotify && (isHoveringVolume || isScrubbingVolume)
    }

    private func sendVolumeThrottled(_ target: Int) {
        guard target != lastVolumeSent else { return }
        let now = Date()
        guard now.timeIntervalSince(lastVolumeSendAt) >= scrubThrottle else { return }
        lastVolumeSent = target
        lastVolumeSendAt = now
        currentVolume = target
        isMuted = target == 0
        SpotifyBridge.setVolume(target)
    }

    private func sendPositionThrottled(_ seconds: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastPositionSendAt) >= scrubThrottle else { return }
        lastPositionSendAt = now
        currentPosition = seconds
        SpotifyBridge.setPlaybackPosition(seconds)
    }

    private var isSpotify: Bool {
        state.app?.bundleIdentifier == "com.spotify.client"
    }

    private func scheduleVolumeVisibility(_ hovering: Bool) {
        volumeHideWorkItem?.cancel()
        volumeHideWorkItem = nil
        if hovering {
            isHoveringVolume = true
        } else {
            let work = DispatchWorkItem { isHoveringVolume = false }
            volumeHideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
    }

    private var volumeScrubber: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let displayVolume = isScrubbingVolume ? scrubVolume : Double(currentVolume)
            let fillWidth = max(0, min(totalWidth, totalWidth * CGFloat(displayVolume / 100)))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 3)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary)
                    .frame(width: fillWidth, height: 3)
                Circle()
                    .fill(Color.primary)
                    .frame(width: 10, height: 10)
                    .offset(x: max(0, min(fillWidth - 5, totalWidth - 10)))
            }
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isScrubbingVolume = true
                        let fraction = max(0, min(1, value.location.x / totalWidth))
                        scrubVolume = Double(fraction) * 100
                        sendVolumeThrottled(Int(scrubVolume.rounded()))
                    }
                    .onEnded { value in
                        let fraction = max(0, min(1, value.location.x / totalWidth))
                        let target = Int((Double(fraction) * 100).rounded())
                        currentVolume = target
                        isMuted = target == 0
                        if target != lastVolumeSent {
                            SpotifyBridge.setVolume(target)
                            lastVolumeSent = target
                            lastVolumeSendAt = Date()
                        }
                        isScrubbingVolume = false
                    }
            )
        }
        .frame(height: 10)
    }

    private func loadPlaybackInfo() {
        guard let app = state.app else { return }
        let isSpotifyStartupSuppressed = isSpotify && SpotifyPlaybackStartupGuard.isSuppressingReads

        // Track change detection
        let trackId = "\(state.trackName ?? "")||\(state.artistName ?? "")"
        let trackChanged = trackId != lastTrackId
        if trackChanged {
            lastTrackId = trackId
            if isSpotify && state.isPlaying && !isSpotifyStartupSuppressed {
                spotifyTrackStartupGraceUntil = Date().addingTimeInterval(spotifyTrackStartupGracePeriod)
            }
        }

        if isSpotifyStartupSuppressed {
            return
        }

        if isSpotify, Date() < spotifyTrackStartupGraceUntil {
            return
        }

        // Always fetch position (lightweight local AppleScript)
        if !isScrubbing, let position = AppleScriptHelper.getPlaybackPosition(from: app) {
            self.currentPosition = position
        }

        if let dur = AppleScriptHelper.getTrackDuration(from: app) {
            self.duration = dur
        }
    }
}

/// Hover-triggered marquee for overflowing text
struct HoverMarquee: View {
    let text: String
    var delay: Double = 0.8
    var speed: Double = 20.0 // points per second

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isHovering: Bool = false

    var body: some View {
        GeometryReader { geo in
            let available = geo.size.width
            ZStack(alignment: .leading) {
                Text(text)
                    .lineLimit(1)
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { textWidth = proxy.size.width }
                        }
                    )
                    .offset(x: offset)
                    .animation(.linear(duration: animationDuration(available: available))
                        .repeatForever(autoreverses: false), value: offset)
            }
            .onAppear {
                containerWidth = available
            }
            .onChange(of: available) { _, newValue in
                containerWidth = newValue
                reset()
            }
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    startIfNeeded()
                } else {
                    reset()
                }
            }
            .clipped()
        }
    }

    private func startIfNeeded() {
        guard textWidth > containerWidth else { return }
        offset = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard isHovering else { return }
            offset = -(textWidth - containerWidth + 12) // slight gap
        }
    }

    private func reset() {
        offset = 0
    }

    private func animationDuration(available: CGFloat) -> Double {
        let distance = max(textWidth - available, 0)
        if distance == 0 { return 0.1 }
        return Double(distance) / speed
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
        let appDetector = MediaAppDetector()
        let stateManager = PlaybackStateManager()

        StatusBarView()
            .environmentObject(stateManager)
            .environmentObject(PreferencesManager.shared)
            .environmentObject(SmartRouter(
                appDetector: appDetector,
                commandSender: MediaCommandSender(),
                preferences: PreferencesManager.shared,
                stateManager: stateManager
            ))
    }
}
#endif
