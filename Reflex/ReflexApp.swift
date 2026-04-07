import SwiftUI
import Combine

@main
struct ReflexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window - this is a menu bar app
        Settings {
            EmptyView()
        }
    }
}

/// Main application delegate handling app lifecycle and manager coordination
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Singleton Managers

    private let accessibilityManager = AccessibilityManager.shared
    private let preferencesManager = PreferencesManager.shared
    private let logger = Logger.shared

    // MARK: - Instance Managers

    private var appDetector: MediaAppDetector!
    private var commandSender: MediaCommandSender!
    private var stateManager: PlaybackStateManager!
    private var smartRouter: SmartRouter!
    private var mediaKeyListener: MediaKeyListener!
    private var nowPlayingManager: NowPlayingManager!
    private var systemNowPlayingMonitor: SystemNowPlayingMonitor!
    private var statusBarManager: StatusBarManager!
    private var coreAudioActivityMonitor: CoreAudioActivityMonitor?

    /// Stores the play/pause decision between shouldConsumeMediaKey (tap thread)
    /// and onMediaKeyPressed (main thread). Protected by a lock.
    private var _lastDecisionLock = os_unfair_lock()
    private var _lastPlayPauseDecision: SmartRouter.PlayPauseDecision = .passThrough

    private func setLastPlayPauseDecision(_ decision: SmartRouter.PlayPauseDecision) {
        os_unfair_lock_lock(&_lastDecisionLock)
        _lastPlayPauseDecision = decision
        os_unfair_lock_unlock(&_lastDecisionLock)
    }

    private func getLastPlayPauseDecision() -> SmartRouter.PlayPauseDecision {
        os_unfair_lock_lock(&_lastDecisionLock)
        defer { os_unfair_lock_unlock(&_lastDecisionLock) }
        return _lastPlayPauseDecision
    }

    // MARK: - Windows

    private var onboardingWindow: NSWindow?
    private var preferencesWindow: NSWindow?

    // MARK: - Observers

    private var cancellables = Set<AnyCancellable>()

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Reflex starting...")

        // Initialize managers in dependency order
        initializeManagers()

        // Setup status bar
        setupStatusBar()

        // Setup notification observers
        setupObservers()

        // Check if onboarding is needed
        if preferencesManager.needsOnboarding {
            showOnboarding()
        }

        // Always try to start listening - even during onboarding
        // The tap creation will fail if we don't have permission, which is fine
        startMediaKeyListening()

        // Retry periodically in case permission is granted later
        startRetryTimer()

        logger.info("Reflex ready")
    }

    private var retryTimer: Timer?

    private func startRetryTimer() {
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !self.mediaKeyListener.isListening {
                self.logger.debug("Retrying to start media key listener...")
                let started = self.mediaKeyListener.startListening()
                self.statusBarManager.setPermissionWarningVisible(!started)
            } else {
                // Successfully listening, stop retrying
                self.retryTimer?.invalidate()
                self.retryTimer = nil
                self.statusBarManager.hidePermissionWarningIndicator()
                self.logger.info("Media key listener is active, stopped retry timer")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Reflex shutting down...")
        mediaKeyListener?.stopListening()
        nowPlayingManager?.unregister()
        smartRouter?.stopPolling()
        systemNowPlayingMonitor?.stopMonitoring()
        if #available(macOS 14.2, *) {
            coreAudioActivityMonitor?.stop()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running when windows are closed (menu bar app)
        return false
    }

    // MARK: - Initialization

    private func initializeManagers() {
        logger.debug("Initializing managers...")

        // Create managers
        appDetector = MediaAppDetector()
        commandSender = MediaCommandSender()
        stateManager = PlaybackStateManager()

        // Create router with dependencies
        smartRouter = SmartRouter(
            appDetector: appDetector,
            commandSender: commandSender,
            preferences: preferencesManager,
            stateManager: stateManager
        )

        // Create system now-playing monitor for browser detection
        // TODO: remove after Core Audio browser detection is proven stable
        systemNowPlayingMonitor = SystemNowPlayingMonitor()
        systemNowPlayingMonitor.startMonitoring(interval: 2.0)

        // Create media key listener (CGEvent tap — belt-and-suspenders with NowPlayingManager)
        mediaKeyListener = MediaKeyListener()

        // Synchronous decision callback — runs on CGEvent tap thread.
        // Only reads thread-safe cached state, no AppleScript.
        mediaKeyListener.shouldConsumeMediaKey = { [weak self] command in
            guard let self = self else { return true }

            switch command {
            case .playPause:
                // Prefer Core Audio's process-output signal on macOS 14.2+; fall back
                // to SystemNowPlayingMonitor on older systems or if the monitor is nil.
                let browserIsNowPlaying: Bool
                if #available(macOS 14.2, *), let coreAudio = self.coreAudioActivityMonitor {
                    browserIsNowPlaying = coreAudio.isBrowserOutputtingAudio
                } else {
                    browserIsNowPlaying = self.systemNowPlayingMonitor.isBrowserNowPlaying
                }
                let decision = self.smartRouter.decidePlayPause(
                    browserIsNowPlaying: browserIsNowPlaying
                )
                self.setLastPlayPauseDecision(decision)
                return decision != .passThrough

            case .nextTrack, .previousTrack:
                // For skip commands, consume only if Spotify is playing
                return self.smartRouter.isSpotifyPlaying

            default:
                return true
            }
        }

        // Async action callback — runs on main thread after the swallow decision.
        mediaKeyListener.onMediaKeyPressed = { [weak self] command in
            guard let self = self else { return }

            switch command {
            case .playPause:
                self.smartRouter.executePlayPauseDecision(self.getLastPlayPauseDecision())

            case .nextTrack, .previousTrack:
                self.smartRouter.routeCommand(command, requirePlaying: true)

            default:
                self.smartRouter.routeCommand(command, requirePlaying: false)
            }
        }

        // Register as the system Now Playing client so mediaremoted sends
        // media key commands to Reflex instead of browsers.
        nowPlayingManager = NowPlayingManager()
        nowPlayingManager.onRemoteCommand = { [weak self] command in
            // Only require an actively-playing app for next/previous track.
            // play, pause, and playPause should always reach the target app.
            let requirePlaying = command == .nextTrack || command == .previousTrack
            self?.smartRouter.routeCommand(command, requirePlaying: requirePlaying)
        }
        nowPlayingManager.register()

        // Keep Now Playing info in sync with playback state
        stateManager.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.nowPlayingManager.updateNowPlaying(
                    playing: state?.isPlaying ?? false,
                    track: state?.trackName,
                    artist: state?.artistName,
                    album: state?.albumName
                )
            }
            .store(in: &cancellables)

        // Create status bar manager
        statusBarManager = StatusBarManager()

        // Start Core Audio activity monitor for logging (macOS 14.2+ only)
        if #available(macOS 14.2, *) {
            let monitor = CoreAudioActivityMonitor()

            monitor.onActiveOutputsChanged = { [weak self] bundleIds in
                guard let self = self else { return }
                let label = bundleIds.isEmpty
                    ? "(none)"
                    : bundleIds.sorted().joined(separator: ", ")
                DispatchQueue.main.async {
                    self.logger.info("CoreAudioActivityMonitor: active output bundles=\(label)")
                }
            }

            monitor.onProcessOutputChanged = { [weak self] pid, bundleId, isRunningOutput in
                guard let self = self else { return }
                let bundleLabel = bundleId ?? "(unknown)"
                DispatchQueue.main.async {
                    self.logger.info("CoreAudioActivityMonitor: output changed pid=\(pid) bundle=\(bundleLabel) runningOutput=\(isRunningOutput)")
                }
            }

            monitor.start()
            coreAudioActivityMonitor = monitor
        } else {
            logger.info("CoreAudioActivityMonitor: Core Audio activity monitoring unavailable (requires macOS 14.2+)")
        }

        logger.debug("Managers initialized")
    }

    private func setupStatusBar() {
        statusBarManager.setup(
            stateManager: stateManager,
            preferences: preferencesManager,
            router: smartRouter,
            appDetector: appDetector
        )
    }

    private func setupObservers() {
        // Listen for preferences window request
        NotificationCenter.default.publisher(for: Notification.Name("openPreferences"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.showPreferences()
            }
            .store(in: &cancellables)

        // Listen for permission changes - try to start listening when permission is granted
        accessibilityManager.$hasPermission
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasPermission in
                guard let self = self else { return }
                self.logger.info("Permission status changed: \(hasPermission)")
                if hasPermission {
                    // Try to start listening if not already
                    if !self.mediaKeyListener.isListening {
                        self.logger.info("Permission granted, starting media key listener...")
                        let started = self.mediaKeyListener.startListening()
                        self.statusBarManager.setPermissionWarningVisible(!started)
                        if started && self.preferencesManager.prefs.autoSwitchEnabled {
                            self.smartRouter.startPolling()
                        }
                    }
                }
            }
            .store(in: &cancellables)

        logger.debug("Observers setup complete")
    }

    // MARK: - Media Key Listening

    private func startMediaKeyListening() {
        if !accessibilityManager.checkPermission() {
            logger.warning("Accessibility not currently trusted; attempting media key listener startup anyway")
        }

        let started = mediaKeyListener.startListening()
        statusBarManager.setPermissionWarningVisible(!started)
        guard started else { return }

        // Start playback state polling if auto-switch is enabled
        if preferencesManager.prefs.autoSwitchEnabled {
            smartRouter.startPolling()
        }
    }

    // MARK: - Windows

    private func showOnboarding() {
        logger.info("Showing onboarding")

        let contentView = WelcomeView()
            .environmentObject(preferencesManager)
            .environmentObject(appDetector)

        onboardingWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 580),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        onboardingWindow?.title = "Welcome to Reflex"
        onboardingWindow?.center()
        onboardingWindow?.contentView = NSHostingView(rootView: contentView)
        onboardingWindow?.isReleasedWhenClosed = false

        // Handle window close
        onboardingWindow?.delegate = self

        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showPreferences() {
        logger.info("Showing preferences")

        // If window exists, just bring it to front
        if let window = preferencesWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = PreferencesWindow()
            .environmentObject(preferencesManager)
            .environmentObject(appDetector)

        preferencesWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        preferencesWindow?.title = "Reflex Preferences"
        preferencesWindow?.center()
        preferencesWindow?.contentView = NSHostingView(rootView: contentView)
        preferencesWindow?.isReleasedWhenClosed = false

        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        // Handle onboarding window close
        if window == onboardingWindow {
            // If user closed without completing, mark as completed anyway
            // to avoid showing again
            if !preferencesManager.prefs.hasCompletedOnboarding {
                preferencesManager.completeOnboarding()
            }
            startMediaKeyListening()
        }
    }
}
