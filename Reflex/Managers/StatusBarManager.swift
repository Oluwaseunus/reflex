import Cocoa
import SwiftUI
import Combine

/// Manages the menu bar status item and popover
final class StatusBarManager: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    /// Current app being displayed
    @Published var currentApp: MediaApp?

    /// Current track info (if showing now playing)
    @Published var currentTrack: String?

    /// Whether permission warning should be shown
    @Published var showPermissionWarning: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private var stateManager: PlaybackStateManager?
    private var preferences: PreferencesManager?
    private var router: SmartRouter?
    private var appDetector: MediaAppDetector?

    override init() {
        super.init()
    }

    /// Setup the status bar with dependencies
    func setup(stateManager: PlaybackStateManager,
               preferences: PreferencesManager,
               router: SmartRouter,
               appDetector: MediaAppDetector) {
        self.stateManager = stateManager
        self.preferences = preferences
        self.router = router
        self.appDetector = appDetector

        createStatusItem()
        setupObservers()

        Logger.shared.info("Status bar manager setup complete")
    }

    /// Create the status bar item
    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else {
            Logger.shared.error("Failed to create status bar button")
            return
        }

        // Set initial icon
        if let image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Reflex") {
            image.isTemplate = true
            button.image = image
        }

        button.action = #selector(statusBarButtonClicked(_:))
        button.target = self

        // Support both left and right click
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        Logger.shared.info("Status bar item created")
    }

    /// Setup observers for state changes
    private func setupObservers() {
        // Observe playback state changes
        stateManager?.$currentState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateDisplay(state: state)
            }
            .store(in: &cancellables)

        // Observe active app changes
        router?.$activeApp
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                self?.currentApp = app
            }
            .store(in: &cancellables)

        // Observe command sent notifications for feedback
        NotificationCenter.default.publisher(for: Constants.Notifications.commandSent)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.flashIcon()
            }
            .store(in: &cancellables)

        // Observe permission changes
        AccessibilityManager.shared.$hasPermission
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasPermission in
                self?.showPermissionWarning = !hasPermission
            }
            .store(in: &cancellables)
    }

    /// Update the status bar display based on current state
    private func updateDisplay(state: PlaybackState?) {
        guard let button = statusItem?.button,
              let prefs = preferences?.prefs else { return }

        if let state = state, state.isPlaying, prefs.showNowPlaying {
            // Show now playing info
            if prefs.showTrackInfo, let track = state.trackName {
                // Show track name (truncated)
                let truncatedTrack = track.count > 30 ? String(track.prefix(27)) + "..." : track
                button.title = " \(truncatedTrack)"
            } else if let appName = state.app?.name {
                // Just show app name
                button.title = " \(appName)"
            }

            // Update icon to match playing app
            if let iconName = state.app?.icon,
               let image = NSImage(systemSymbolName: iconName, accessibilityDescription: state.app?.name) {
                image.isTemplate = true
                button.image = image
            }

            currentTrack = state.trackName
        } else {
            // Reset to default
            button.title = ""
            if let image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Reflex") {
                image.isTemplate = true
                button.image = image
            }
            currentTrack = nil
        }
    }

    /// Handle status bar button click
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    /// Toggle the popover
    func togglePopover() {
        if let popover = popover, popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    /// Show the popover
    func showPopover() {
        guard let button = statusItem?.button,
              let stateManager = stateManager,
              let preferences = preferences,
              let router = router,
              let appDetector = appDetector else { return }

        if popover == nil {
            popover = NSPopover()
            popover?.behavior = .transient
            popover?.animates = true

            // Create the SwiftUI view with environment objects
            let contentView = StatusBarView()
                .environmentObject(stateManager)
                .environmentObject(preferences)
                .environmentObject(router)
                .environmentObject(appDetector)

            popover?.contentViewController = NSHostingController(rootView: contentView)
        }

        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        Logger.shared.debug("Popover shown")
    }

    /// Close the popover
    func closePopover() {
        popover?.performClose(nil)
        Logger.shared.debug("Popover closed")
    }

    /// Show context menu
    private func showMenu() {
        let menu = NSMenu()

        // Now Playing section
        if let state = stateManager?.currentState, state.isPlaying {
            let nowPlayingItem = NSMenuItem(title: "Now Playing:", action: nil, keyEquivalent: "")
            nowPlayingItem.isEnabled = false
            menu.addItem(nowPlayingItem)

            if let app = state.app {
                let appItem = NSMenuItem(title: "  \(app.name)", action: nil, keyEquivalent: "")
                appItem.isEnabled = false
                menu.addItem(appItem)
            }

            if let track = state.trackName {
                let trackItem = NSMenuItem(title: "  \(track)", action: nil, keyEquivalent: "")
                trackItem.isEnabled = false
                menu.addItem(trackItem)
            }

            menu.addItem(NSMenuItem.separator())
        }

        // Quick switch apps
        let switchItem = NSMenuItem(title: "Switch App", action: nil, keyEquivalent: "")
        let switchSubmenu = NSMenu()

        for app in appDetector?.runningApps ?? [] {
            let appItem = NSMenuItem(
                title: app.name,
                action: #selector(selectApp(_:)),
                keyEquivalent: ""
            )
            appItem.target = self
            appItem.representedObject = app
            if app.id == router?.activeApp?.id {
                appItem.state = .on
            }
            switchSubmenu.addItem(appItem)
        }

        if switchSubmenu.items.isEmpty {
            let noAppsItem = NSMenuItem(title: "No apps running", action: nil, keyEquivalent: "")
            noAppsItem.isEnabled = false
            switchSubmenu.addItem(noAppsItem)
        }

        switchItem.submenu = switchSubmenu
        menu.addItem(switchItem)

        menu.addItem(NSMenuItem.separator())

        // Preferences
        menu.addItem(NSMenuItem(
            title: "Preferences...",
            action: #selector(openPreferences),
            keyEquivalent: ","
        ))

        menu.addItem(NSMenuItem.separator())

        // Quit
        menu.addItem(NSMenuItem(
            title: "Quit Reflex",
            action: #selector(quit),
            keyEquivalent: "q"
        ))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func selectApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? MediaApp else { return }
        router?.selectApp(app)
    }

    @objc private func openPreferences() {
        // Open preferences window
        NotificationCenter.default.post(name: Notification.Name("openPreferences"), object: nil)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    /// Flash the icon to indicate an action
    func flashIcon() {
        guard let button = statusItem?.button,
              preferences?.prefs.showVisualFeedback == true else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Constants.Timing.feedbackAnimationDuration
            button.animator().alphaValue = 0.3
        } completionHandler: {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Constants.Timing.feedbackAnimationDuration
                button.animator().alphaValue = 1.0
            }
        }
    }

    /// Show a warning indicator that permission is needed
    func showPermissionWarningIndicator() {
        guard let button = statusItem?.button else { return }

        if let image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Permission Required") {
            image.isTemplate = true
            button.image = image
        }
        showPermissionWarning = true
    }
}
