import SwiftUI
import Combine
import AppKit

/// Main popover view shown when clicking the status bar icon
struct StatusBarView: View {
    @EnvironmentObject var stateManager: PlaybackStateManager
    @EnvironmentObject var preferences: PreferencesManager
    @EnvironmentObject var router: SmartRouter

    @State private var showingPreferences = false

    var body: some View {
        VStack(spacing: 0) {
            if let state = stateManager.currentState {
                NowPlayingCard(state: state, router: router, stateManager: stateManager)
                if state.app?.bundleIdentifier == "com.spotify.client" {
                    SpotifyDeviceMenu()
                }
            } else {
                headerSection
                    .padding()
            }

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
        }
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
                    Text("Settings...")
                        .font(.system(size: 13))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.primary)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .popoverFocusHighlight()

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
            .padding(.horizontal)
            .padding(.vertical, 8)
            .popoverFocusHighlight()
        }
        .background(VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow))
    }

}

/// Modern Now Playing card with album art, controls, and progress
struct NowPlayingCard: View {
    @EnvironmentObject private var preferences: PreferencesManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// When the ⏮ button is clicked, positions strictly less than this
    /// threshold (in seconds) go to the previous track; positions at or
    /// above it restart the current track. Matches Spotify's native UI
    /// behavior for the ⏮ button.
    private static let restartThresholdSeconds: Double = 3.0
    private static let keyboardSeekStepSeconds: Double = 5.0
    private static let keyboardVolumeStep = 5

    private enum FocusedScrubber: Hashable {
        case playbackPosition
        case volume
    }

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
    @FocusState private var focusedScrubber: FocusedScrubber?

    private let scrubThrottle: TimeInterval = 0.03
    private let spotifyTrackStartupGracePeriod: TimeInterval = 2.0

    var body: some View {
        VStack(spacing: 0) {
            // App indicator and volume
            HStack {
                Text("• \(state.app?.name.uppercased() ?? "UNKNOWN") •")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(!usesArtworkBackground ? .secondary : .white.opacity(0.85))
                    .tracking(1)
                Spacer()
                volumeControl
                    .environment(\.colorScheme, !usesArtworkBackground ? colorScheme : .dark)

                if !state.isPlaying {
                    Button(action: { stateManager.dismissCurrentTrack() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 14, height: 14, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(!usesArtworkBackground ? .secondary : .white.opacity(0.85))
                    .help("Dismiss from menu bar")
                    .popoverFocusHighlight()
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
                .disabled(!canOpenTrack)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                .popoverFocusHighlight(cornerRadius: 8)

                // Right side: Track info, controls, and progress
                VStack(alignment: .leading, spacing: 0) {
                    // Track name with hover marquee
                    Button(action: openTrackLink) {
                        HoverMarquee(text: state.trackName ?? "Unknown Track")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 18, alignment: .leading)
                            .accessibilityLabel(state.trackName ?? "Unknown Track")
                    }
                    .buttonStyle(.plain)
                    .disabled(!canOpenTrack)
                    .popoverFocusHighlight()

                    Button(action: openAlbumLink) {
                        Text(state.albumName ?? "Unknown Album")
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundColor(!usesArtworkBackground ? .secondary : .white.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 14, alignment: .leading)
                            .accessibilityLabel(state.albumName ?? "Unknown Album")
                    }
                    .buttonStyle(.plain)
                    .disabled(!canOpenAlbum)
                    .padding(.top, 2)
                    .popoverFocusHighlight()

                    Button(action: openArtistLink) {
                        HoverMarquee(text: state.artistName ?? "Unknown Artist")
                            .font(.system(size: 11))
                            .foregroundColor(!usesArtworkBackground ? .secondary : .white.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 14, alignment: .leading)
                            .accessibilityLabel(state.artistName ?? "Unknown Artist")
                    }
                    .buttonStyle(.plain)
                    .disabled(!canOpenArtist)
                    .padding(.top, 2)
                    .popoverFocusHighlight()

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
                        .popoverFocusHighlight()

                    Spacer(minLength: 16)

                    Button(action: { sendCommand(.playPause) }) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.primary)
                            .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .popoverFocusHighlight()

                        Spacer(minLength: 16)

                        Button(action: { sendCommand(.nextTrack) }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        .popoverFocusHighlight()

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
                                    .fill(!usesArtworkBackground ? Color(nsColor: .separatorColor) : Color.white.opacity(0.3))
                                    .frame(height: 3)

                                // Progress fill
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.primary)
                                    .frame(width: fillWidth, height: 3)

                                // Scrub handle
                                Circle()
                                    .fill(Color.primary)
                                    .frame(width: 10, height: 10)
                                    .animation(InterfaceMotion.hoverReveal) { content in
                                        content
                                            .opacity(isHoveringProgress || isScrubbing ? 1 : 0)
                                            .scaleEffect(reduceMotion || isHoveringProgress || isScrubbing ? 1 : 0.97)
                                    }
                                    .offset(x: max(0, min(fillWidth - 5, totalWidth - 10)))
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
                                        guard duration > 0 else {
                                            isScrubbing = false
                                            return
                                        }
                                        let fraction = max(0, min(1, value.location.x / totalWidth))
                                        let seekTo = Double(fraction) * duration
                                        setPlaybackPosition(seekTo)
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
                                .foregroundColor(!usesArtworkBackground ? .secondary : .white.opacity(0.85))
                                .frame(minWidth: 46, alignment: .leading)
                            Spacer()
                            Text(formatTime(duration))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(!usesArtworkBackground ? .secondary : .white.opacity(0.85))
                                .frame(minWidth: 46, alignment: .trailing)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Playback position")
                    .accessibilityValue("\(accessibilityTime(isScrubbing ? scrubPosition : currentPosition)) of \(accessibilityTime(duration))")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment:
                            adjustPlaybackPosition(by: Self.keyboardSeekStepSeconds)
                        case .decrement:
                            adjustPlaybackPosition(by: -Self.keyboardSeekStepSeconds)
                        @unknown default:
                            break
                        }
                    }
                    .focusable(duration > 0)
                    .focused($focusedScrubber, equals: .playbackPosition)
                    .onMoveCommand { direction in
                        switch direction {
                        case .right, .up:
                            adjustPlaybackPosition(by: Self.keyboardSeekStepSeconds)
                        case .left, .down:
                            adjustPlaybackPosition(by: -Self.keyboardSeekStepSeconds)
                        default:
                            break
                        }
                    }
                    .popoverFocusAppearance(focusedScrubber == .playbackPosition, cornerRadius: 4)
                }
                .frame(height: 120)
                .environment(\.colorScheme, !usesArtworkBackground ? colorScheme : .dark)
            }
        }
            .padding(14)
            .background {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                    .overlay { artworkBackdrop }
            }
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
        .onDisappear {
            timerCancellable?.cancel()
            timerCancellable = nil
            volumeHideWorkItem?.cancel()
            volumeHideWorkItem = nil
            isHoveringVolume = false
            isScrubbingVolume = false
            focusedScrubber = nil
        }
    }

    private var usesArtworkBackground: Bool {
        preferences.prefs.useAlbumArtworkBackground && stateManager.currentArtwork != nil
    }

    /// Fill the entire top card without changing the artwork or the card's layout.
    /// The fixed dark scrim keeps even white cover art behind readable controls.
    private var artworkBackdrop: some View {
        GeometryReader { geometry in
            if usesArtworkBackground, let artwork = stateManager.currentArtwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(1.1)
                    .blur(radius: 10, opaque: true)
                    .overlay(Color.black.opacity(colorSchemeContrast == .increased ? 0.85 : 0.72))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        guard canOpenAlbum else { return }
        guard let album = state.albumName else { return }
        let uri = AppleScriptHelper.spotifyAlbumSearchURI(album: album, artist: state.artistName)
        AppleScriptHelper.openSpotifyURI(uri)
    }

    private func openArtistLink() {
        guard canOpenArtist else { return }
        guard let artist = state.artistName else { return }
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

    private func accessibilityTime(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        let minuteUnit = minutes == 1 ? "minute" : "minutes"
        let secondUnit = remainingSeconds == 1 ? "second" : "seconds"
        return "\(minutes) \(minuteUnit), \(remainingSeconds) \(secondUnit)"
    }

    private func adjustPlaybackPosition(by offset: Double) {
        setPlaybackPosition(currentPosition + offset)
    }

    private func setPlaybackPosition(_ seconds: Double) {
        guard duration > 0, let app = state.app else { return }
        let target = max(0, min(seconds, duration))
        currentPosition = target
        if isSpotify {
            SpotifyBridge.setPlaybackPosition(target)
        } else {
            AppleScriptHelper.setPlaybackPosition(target, for: app)
        }
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
        if let vol = AppleScriptHelper.getVolume(for: app) {
            currentVolume = vol
            isMuted = vol == 0
        }
    }

    private func syncVolumeState() {
        guard let app = state.app else { return }
        guard !isScrubbingVolume else { return }
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

    private var volumeControl: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button(action: toggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 14, height: 14, alignment: .center)
            }
            .buttonStyle(.plain)
            .foregroundColor(!usesArtworkBackground ? .secondary : .white.opacity(0.85))
            .help(isMuted ? "Unmute Spotify" : "Mute Spotify")
            .focusEffectDisabled()
        }
        // Reserve the slider's space so neither the icon nor app label reflows.
        .frame(width: isSpotify ? 124 : 14, height: 14)
        .overlay(alignment: .leading) {
            if isSpotify {
                volumeScrubber
                    .frame(width: 100)
                    .scaleEffect(x: reduceMotion || showVolumeScrubber ? 1 : 0.03,
                                 y: 1, anchor: .trailing)
                    .mask {
                        Rectangle()
                            .scaleEffect(x: showVolumeScrubber ? 1 : 0,
                                         y: 1, anchor: .trailing)
                    }
                    .animation(reduceMotion ? nil : (showVolumeScrubber
                               ? InterfaceMotion.volumeReveal : InterfaceMotion.hoverReveal),
                               value: showVolumeScrubber)
                    .allowsHitTesting(showVolumeScrubber)
                    .accessibilityHidden(!showVolumeScrubber)
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            guard isSpotify else { return }
            switch phase {
            case .active(let location):
                // A hidden slider is not a hover trigger. Once the icon opens
                // it, the entire region bridges pointer travel to the slider.
                scheduleVolumeVisibility(location.x >= 110 || showVolumeScrubber)
            case .ended:
                scheduleVolumeVisibility(false)
            }
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
                        setVolume(target)
                        isScrubbingVolume = false
                    }
            )
        }
        .frame(height: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spotify volume")
        .accessibilityValue("\(currentVolume) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                adjustVolume(by: Self.keyboardVolumeStep)
            case .decrement:
                adjustVolume(by: -Self.keyboardVolumeStep)
            @unknown default:
                break
            }
        }
        .focusable(showVolumeScrubber)
        .focused($focusedScrubber, equals: .volume)
        .onMoveCommand { direction in
            switch direction {
            case .right, .up:
                adjustVolume(by: Self.keyboardVolumeStep)
            case .left, .down:
                adjustVolume(by: -Self.keyboardVolumeStep)
            default:
                break
            }
        }
        .popoverFocusAppearance(focusedScrubber == .volume, cornerRadius: 4)
    }

    private func adjustVolume(by offset: Int) {
        setVolume(currentVolume + offset)
    }

    private func setVolume(_ volume: Int) {
        let target = max(0, min(volume, 100))
        currentVolume = target
        isMuted = target == 0
        guard target != lastVolumeSent else { return }
        SpotifyBridge.setVolume(target)
        lastVolumeSent = target
        lastVolumeSendAt = Date()
    }

    private func loadPlaybackInfo() {
        guard let app = state.app else { return }

        // Track change detection
        let trackId = "\(state.trackName ?? "")||\(state.artistName ?? "")"
        let trackChanged = trackId != lastTrackId
        if trackChanged {
            lastTrackId = trackId
            if isSpotify && state.isPlaying {
                spotifyTrackStartupGraceUntil = Date().addingTimeInterval(spotifyTrackStartupGracePeriod)
            }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    var delay: Double = 0.8
    var speed: Double = 20.0 // points per second

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isHovering: Bool = false
    @State private var showsFullText: Bool = false
    @State private var hoverGeneration: Int = 0

    var body: some View {
        GeometryReader { geo in
            let available = geo.size.width
            ZStack(alignment: .leading) {
                Text(text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: available, alignment: .leading)
                    .opacity(showsFullText ? 0 : 1)

                Text(text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: offset)
                    .opacity(showsFullText ? 1 : 0)

                Color.clear
                    .overlay(alignment: .leading) {
                        Text(text)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear
                                        .onAppear { textWidth = proxy.size.width }
                                        .onChange(of: proxy.size.width) { _, newValue in
                                            textWidth = newValue
                                        }
                                }
                            )
                            .opacity(0)
                    }
                    .allowsHitTesting(false)
            }
            .frame(width: available, alignment: .leading)
            .onAppear {
                containerWidth = available
            }
            .onChange(of: available) { _, newValue in
                containerWidth = newValue
                if isHovering {
                    startIfNeeded()
                } else {
                    reset()
                }
            }
            .onChange(of: text) { _, _ in
                if isHovering {
                    startIfNeeded()
                } else {
                    reset()
                }
            }
            .onChange(of: textWidth) { _, _ in
                if isHovering {
                    startIfNeeded()
                }
            }
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    startIfNeeded()
                } else {
                    reset()
                }
            }
            .onChange(of: reduceMotion) { _, _ in
                if isHovering {
                    startIfNeeded()
                } else {
                    reset()
                }
            }
            .onDisappear { reset() }
            .contentShape(Rectangle())
            .clipped()
        }
        .help(text)
    }

    private func startIfNeeded() {
        hoverGeneration &+= 1
        let generation = hoverGeneration
        guard !reduceMotion, textWidth > containerWidth else {
            showsFullText = false
            resetOffset()
            return
        }

        showsFullText = true
        resetOffset()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard !reduceMotion, isHovering, generation == hoverGeneration else { return }
            let distance = textWidth - containerWidth
            guard distance > 0 else { return }
            withAnimation(.linear(duration: Double(distance) / speed)) {
                offset = -distance
            }
        }
    }

    private func reset() {
        hoverGeneration &+= 1
        withTransaction(Transaction(animation: nil)) {
            showsFullText = false
            offset = 0
        }
    }

    private func resetOffset() {
        withTransaction(Transaction(animation: nil)) {
            offset = 0
        }
    }
}

/// Keeps popover buttons keyboard-accessible without SwiftUI's default focus ring.
private struct PopoverFocusHighlight: ViewModifier {
    @FocusState private var isFocused: Bool

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .popoverFocusAppearance(isFocused, cornerRadius: cornerRadius)
    }
}

private extension View {
    func popoverFocusHighlight(cornerRadius: CGFloat = 6) -> some View {
        modifier(PopoverFocusHighlight(cornerRadius: cornerRadius))
    }

    func popoverFocusAppearance(_ isFocused: Bool, cornerRadius: CGFloat) -> some View {
        focusEffectDisabled()
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isFocused ? Color.primary.opacity(0.35) : .clear, lineWidth: 1)
                    .allowsHitTesting(false)
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
