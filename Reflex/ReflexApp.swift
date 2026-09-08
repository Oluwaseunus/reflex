import SwiftUI
import Combine

@main
enum ReflexApp {
    static func main() {
        let app = NSApplication.shared
        let appDelegate = AppDelegate()
        app.delegate = appDelegate
        app.run()
    }
}

/// Main application delegate handling app lifecycle and manager coordination
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Singleton Managers

    private let preferencesManager = PreferencesManager.shared
    private let logger = Logger.shared

    // MARK: - Instance Managers

    private var appDetector: MediaAppDetector!
    private var commandSender: MediaCommandSender!
    private var stateManager: PlaybackStateManager!
    private var smartRouter: SmartRouter!
    private var statusBarManager: StatusBarManager!

    // MARK: - Windows

    private var onboardingWindow: NSWindow?
    private var preferencesWindow: NSWindow?

    // MARK: - Observers

    private var cancellables = Set<AnyCancellable>()

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Reflex starting...")

        setupMainMenu()

        // Initialize managers in dependency order
        initializeManagers()

        // Setup status bar
        setupStatusBar()

        // Setup notification observers
        setupObservers()

        SearchPopupController.shared.configure(stateManager: stateManager)

        // Register global hotkey for Spotify search popup.
        SearchPopupController.shared.registerHotkey()

        // Check if onboarding is needed
        if preferencesManager.needsOnboarding {
            showOnboarding()
        }

        logger.info("Reflex ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Reflex shutting down...")
        smartRouter?.stopPolling()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        statusBarManager?.prepareForTermination()
        SearchPopupController.shared.prepareForTermination()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running when windows are closed (menu bar app)
        return false
    }

    // MARK: - Initialization

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        let preferencesItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        appMenu.addItem(preferencesItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

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

        logger.debug("Observers setup complete")
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

    @objc func showPreferences() {
        logger.info("Showing preferences")

        if let preferencesWindow {
            preferencesWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = PreferencesWindow()
            .environmentObject(preferencesManager)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Reflex Preferences"
        window.center()
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        preferencesWindow = window

        window.makeKeyAndOrderFront(nil)
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
        }
    }
}
