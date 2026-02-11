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
    private var statusBarManager: StatusBarManager!

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
                self.mediaKeyListener.startListening()
            } else {
                // Successfully listening, stop retrying
                self.retryTimer?.invalidate()
                self.retryTimer = nil
                self.logger.info("Media key listener is active, stopped retry timer")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Reflex shutting down...")
        mediaKeyListener?.stopListening()
        smartRouter?.stopPolling()
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

        // Create media key listener
        mediaKeyListener = MediaKeyListener()
        mediaKeyListener.onMediaKeyPressed = { [weak self] command in
            // Only intercept when a registered media app is actively playing
            self?.smartRouter.routeCommand(command, requirePlaying: true) ?? false
        }

        // Create status bar manager
        statusBarManager = StatusBarManager()

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
                        self.mediaKeyListener.startListening()
                        if self.preferencesManager.prefs.autoSwitchEnabled {
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
        // Check permission first
        guard accessibilityManager.checkPermission() else {
            logger.warning("Cannot start media key listening - no permission")
            statusBarManager.showPermissionWarningIndicator()
            return
        }

        mediaKeyListener.startListening()

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
