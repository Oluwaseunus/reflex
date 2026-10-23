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
    private let settingsNavigation = SettingsNavigationModel()
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // A normal Open/Reopen request should reveal a menu-bar app's controls.
        // The status panel itself does not activate Reflex or switch Spaces.
        if !flag { statusBarManager?.showPopover() }
        return false
    }

    // MARK: - Initialization

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        let searchItem = NSMenuItem(
            title: "Search Spotify…",
            action: #selector(openSpotifySearch),
            keyEquivalent: ""
        )
        searchItem.target = self
        appMenu.addItem(searchItem)
        appMenu.addItem(.separator())

        let preferencesItem = NSMenuItem(
            title: "Settings...",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        appMenu.addItem(preferencesItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func openSpotifySearch() {
        Task { @MainActor in
            statusBarManager?.closePopover(restoreFocus: false)
            SearchPopupController.shared.open()
        }
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
        logger.info("Showing settings")

        if let preferencesWindow {
            updateSettingsWindow(for: settingsNavigation.selectedPane)
            preferencesWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = PreferencesWindow(navigation: settingsNavigation)
            .environmentObject(preferencesManager)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        configureSettingsToolbar(for: window)
        updateSettingsWindow(for: settingsNavigation.selectedPane, window: window)
        window.center()
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        preferencesWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureSettingsToolbar(for window: NSWindow) {
        let toolbar = NSToolbar(identifier: NSToolbar.Identifier("com.reflex.settings"))
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconAndLabel
        toolbar.selectedItemIdentifier = settingsNavigation.selectedPane.toolbarItemIdentifier
        window.toolbarStyle = .preference
        window.toolbar = toolbar
    }

    private func updateSettingsWindow(for pane: SettingsPane, window: NSWindow? = nil) {
        let window = window ?? preferencesWindow
        window?.title = pane.rawValue
        window?.toolbar?.selectedItemIdentifier = pane.toolbarItemIdentifier
    }

    @objc private func selectSettingsPane(_ sender: NSToolbarItem) {
        guard let pane = SettingsPane(toolbarItemIdentifier: sender.itemIdentifier) else { return }
        settingsNavigation.selectedPane = pane
        updateSettingsWindow(for: pane)
    }
}

private extension SettingsPane {
    var toolbarItemIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("com.reflex.settings.\(rawValue.lowercased())")
    }

    init?(toolbarItemIdentifier: NSToolbarItem.Identifier) {
        guard let pane = Self.allCases.first(where: { $0.toolbarItemIdentifier == toolbarItemIdentifier }) else {
            return nil
        }
        self = pane
    }
}

extension AppDelegate: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.toolbarItemIdentifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let pane = SettingsPane(toolbarItemIdentifier: itemIdentifier) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = pane.rawValue
        item.paletteLabel = pane.rawValue
        item.image = NSImage(systemSymbolName: pane.icon, accessibilityDescription: pane.rawValue)
        item.target = self
        item.action = #selector(selectSettingsPane(_:))
        return item
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
