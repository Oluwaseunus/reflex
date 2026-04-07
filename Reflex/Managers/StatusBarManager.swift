import Cocoa
import SwiftUI
import Combine

/// Manages the menu bar status item and popover
final class StatusBarManager: NSObject, ObservableObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var closedViaStatusBar: Bool = false
    private var popoverIsOpen: Bool = false

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

        updateDisplay(state: stateManager?.currentState)

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

        AccessibilityManager.shared.$hasPermission
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasPermission in
                self?.setPermissionWarningVisible(!hasPermission)
            }
            .store(in: &cancellables)

    }

    /// Update the status bar display based on current state
    private func updateDisplay(state: PlaybackState?) {
        guard let button = statusItem?.button,
              let prefs = preferences?.prefs else { return }
        guard !popoverIsOpen || prefs.updateMenuBarWhilePopoverOpen else {
            return
        }

        if let state = state, prefs.showNowPlaying {
            // Show now playing info
            if prefs.showTrackInfo, let track = state.trackName {
                var displayText = track
                if prefs.showArtistInMenuBar, let artist = state.artistName, !artist.isEmpty {
                    displayText = "\(track) - \(artist)"
                }
                if !state.isPlaying {
                    displayText = "⏸ " + displayText
                }

                // Truncate to keep menu bar compact
                let truncated = displayText.count > 32 ? String(displayText.prefix(29)) + "..." : displayText
                button.title = " \(truncated)"
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
            currentTrack = nil
        }

        if !popoverIsOpen {
            updateStatusIcon(for: state, button: button)
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
            popover?.delegate = self

            // Create the SwiftUI view with environment objects
            let contentView = StatusBarView()
                .environmentObject(stateManager)
                .environmentObject(preferences)
                .environmentObject(router)
                .environmentObject(appDetector)

            let hostingController = FirstMouseHostingController(rootView: contentView)
            popover?.contentViewController = hostingController
        }

        popoverIsOpen = true

        // Store the currently focused app before we steal focus
        previousApp = NSWorkspace.shared.frontmostApplication

        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Activate the app and make the popover window key so gestures work immediately
        NSApp.activate(ignoringOtherApps: true)
        popover?.contentViewController?.view.window?.makeKeyAndOrderFront(nil)

        startEventMonitor()
        Logger.shared.debug("Popover shown")
    }

    /// Close the popover
    func closePopover() {
        closedViaStatusBar = true
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

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        stopEventMonitor()
        popoverIsOpen = false
        // Apply the latest state now that the popover is closed
        updateDisplay(state: stateManager?.currentState)
        if closedViaStatusBar, preferences?.prefs.restoreFocusOnClose == true,
           let app = previousApp, !app.isTerminated {
            app.activate()
        }
        closedViaStatusBar = false
        previousApp = nil
    }

    // MARK: - Event Monitor

    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self,
                  let popover = self.popover,
                  popover.isShown else { return }

            if let window = popover.contentViewController?.view.window,
               event.window == window {
                return // allow interactions inside
            }

            DispatchQueue.main.async {
                popover.animates = true
                popover.performClose(event)
                self.stopEventMonitor()
            }
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
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
        setPermissionWarningVisible(true)
    }

    func hidePermissionWarningIndicator() {
        setPermissionWarningVisible(false)
    }

    func setPermissionWarningVisible(_ visible: Bool) {
        guard showPermissionWarning != visible else { return }
        showPermissionWarning = visible
        if !popoverIsOpen {
            updateDisplay(state: stateManager?.currentState)
        }
    }

    private func updateStatusIcon(for state: PlaybackState?, button: NSStatusBarButton) {
        let imageName: String
        let description: String

        if showPermissionWarning {
            imageName = "exclamationmark.triangle.fill"
            description = "Accessibility Permission Required"
            button.toolTip = "Accessibility permission is required to capture media keys"
        } else if let iconName = state?.app?.icon {
            imageName = iconName
            description = state?.app?.name ?? "Reflex"
            button.toolTip = nil
        } else {
            imageName = "music.note"
            description = "Reflex"
            button.toolTip = nil
        }

        if let image = NSImage(systemSymbolName: imageName, accessibilityDescription: description) {
            image.isTemplate = true
            button.image = image
        }
    }
}

/// NSHostingController that uses a view which accepts first mouse events.
final class FirstMouseHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        super.loadView()
        view = FirstMouseHostingView(rootView: rootView)
    }
}

/// NSHostingView subclass that accepts first mouse events so clicks
/// register immediately in popovers without a prior activation click.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
