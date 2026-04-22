import AppKit
import SwiftUI
import Combine
import KeyboardShortcuts

final class SearchPopupController: NSObject {
    static let shared = SearchPopupController()
    /// Height of the search-bar row — matches the padding + content heights in
    /// SearchPopupView's `searchBar` (14 + 28 + 14).
    fileprivate static let idleHeight: CGFloat = 56

    private var panel: SearchPanel?
    private var viewModel: SearchViewModel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []
    // Strong ref, not weak: NSWorkspace's cached NSRunningApplication for an
    // app that is no longer frontmost gets released, so a weak reference goes
    // nil the moment Spotify steals focus — leaving nothing to re-activate.
    private var previousApp: NSRunningApplication?

    private override init() { super.init() }

    // MARK: - Hotkey

    func registerHotkey() {
        KeyboardShortcuts.onKeyDown(for: .openSpotifySearch) { [weak self] in
            Task { @MainActor in self?.open() }
        }
    }

    // MARK: - Open / Close

    @MainActor
    func open() {
        if let panel, panel.isVisible { return }

        let panel = self.panel ?? buildPanel()
        self.panel = panel

        previousApp = NSWorkspace.shared.frontmostApplication
        if previousApp?.bundleIdentifier == Bundle.main.bundleIdentifier {
            previousApp = nil
        }

        viewModel?.reset()

        // Idle height is known (just the search bar) — hardcode it instead of
        // measuring fittingSize pre-show. A pre-show fittingSize read tends to
        // differ slightly from the post-show value, which drove the first-open
        // resize flicker. Non-idle state changes still resize via fittingSize
        // in updatePanelSize, which runs after SwiftUI has fully rendered.
        let height = SearchPopupController.idleHeight

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        if let screen {
            let width = panel.frame.width
            let originX = screen.frame.midX - width / 2
            // Pin the top edge so the panel grows downward as results load.
            let topY = screen.frame.midY + screen.frame.height * 0.12
            let originY = topY - height
            panel.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: false)
        }

        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        focusSearchField()
        installMonitors()
    }

    @MainActor
    private func focusSearchField() {
        // On every open, make the text field first responder. The one-shot
        // dispatch inside SearchField.makeNSView only covers the first build;
        // subsequent opens reuse the panel, so focus must be re-asserted here.
        // On the very first open, NSHostingView hasn't materialized the
        // NSTextField synchronously when this runs, so a single async lookup
        // returns nil. Force a layout pass and retry once on the next tick.
        panel?.contentView?.layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let panel = self?.panel else { return }
            if let field = panel.contentView?.findFirstTextField() {
                panel.makeFirstResponder(field)
                return
            }
            DispatchQueue.main.async {
                guard let field = panel.contentView?.findFirstTextField() else { return }
                panel.makeFirstResponder(field)
            }
        }
    }

    @MainActor
    private func updatePanelSize() {
        guard let panel, let content = panel.contentView else { return }
        // Idle state has a known height (just the search bar). Skip fittingSize
        // entirely — SwiftUI's post-show measurement drifts a few points from
        // the hardcoded value and was causing a first-open resize flicker.
        let targetHeight: CGFloat
        if case .idle = viewModel?.state {
            targetHeight = Self.idleHeight
        } else {
            content.layoutSubtreeIfNeeded()
            let fitting = content.fittingSize
            guard fitting.height > 0 else { return }
            targetHeight = fitting.height
        }
        let current = panel.frame
        // Keep the top edge pinned so content grows/shrinks downward.
        let topY = current.maxY
        let newFrame = NSRect(
            x: current.origin.x,
            y: topY - targetHeight,
            width: current.width,
            height: targetHeight
        )
        if abs(newFrame.height - current.height) > 0.5 {
            panel.setFrame(newFrame, display: true, animate: false)
        }
    }

    @MainActor
    func close(restoreFocus: Bool = true) {
        removeMonitors()
        panel?.orderOut(nil)
        // Re-activate the app that had focus before the popup opened. Mouse
        // click-away close paths opt out so the clicked target keeps focus.
        if restoreFocus, let prev = previousApp, prev.isTerminated == false {
            prev.activate()
        }
        previousApp = nil
        viewModel?.reset()
    }

    @MainActor
    func closeAfterPlayback() {
        close(restoreFocus: true)
    }

    // MARK: - Build

    @MainActor
    private func buildPanel() -> SearchPanel {
        let search = SpotifySearchProvider()
        let playback = SpotifyPlaybackProvider()
        let vm = SearchViewModel(search: search, playback: playback)
        self.viewModel = vm

        // dropFirst: @Published delivers its current value on subscribe, which
        // would queue a post-show resize the first time open() runs — SwiftUI's
        // fittingSize after the window is on screen drifts a few pixels from
        // the pre-show measurement, causing a visible flicker below the search
        // bar on the very first open. We only care about *transitions* (idle →
        // loading → results/empty/error), so skip the initial replay.
        vm.$state
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updatePanelSize() }
            }
            .store(in: &cancellables)

        let hosting = NSHostingView(rootView: SearchPopupView(viewModel: vm))
        hosting.frame = NSRect(x: 0, y: 0, width: 620, height: 56)

        let panel = SearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 56),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // Disable macOS's default window fade-in. The fade composites the
        // panel's shadow against the backdrop and on first show this reads as
        // a brief "popup" rectangle under the search bar before the panel
        // settles to full opacity.
        panel.animationBehavior = .none
        panel.contentView = hosting
        return panel
    }

    // MARK: - Monitors

    @MainActor
    private func installMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.close(restoreFocus: false) }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window !== panel {
                Task { @MainActor in self.close(restoreFocus: false) }
            }
            return event
        }

        // Panel-level Esc + Cmd+Enter: catches these regardless of which view
        // holds focus. Cmd+Enter in particular needs to land here — NSTextField's
        // field editor doesn't reliably route it to doCommandBy (macOS treats it
        // as a key equivalent), so the SearchField coordinator never sees it.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            if event.keyCode == 53 { // Escape
                Task { @MainActor in self.close(restoreFocus: true) }
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 76 {
                // Cmd/Shift+Return must be intercepted here — macOS routes
                // modified Return as a key equivalent that bypasses the field
                // editor's insertNewline: selector, and single-line mode
                // suppresses insertLineBreak:.
                if event.modifierFlags.contains(.command) {
                    Task { @MainActor in self.viewModel?.onCommandEnterPressed() }
                    return nil
                }
                if event.modifierFlags.contains(.shift) {
                    Task { @MainActor in self.viewModel?.onShiftEnterPressed() }
                    return nil
                }
            }
            return event
        }

        // Close when the panel loses key status (Cmd+Tab, clicking on another
        // app's window, etc). Since we no longer call NSApp.activate on open,
        // the app never becomes frontmost — so didResignActiveNotification
        // never fires, but panel key loss still does.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }

        // Close at the *start* of app/space navigation, not at the end. The
        // didResignKey / didActiveSpaceChange notifications fire after macOS
        // commits the transition, so the popup lingers through the whole
        // animation. Watching the keydown globally lets us dismiss as soon as
        // the gesture begins.
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let flags = event.modifierFlags
            let code = event.keyCode
            // Cmd+Tab (48) / Cmd+` (50): app / window switching.
            let isAppSwitch = flags.contains(.command) && (code == 48 || code == 50)
            // Ctrl+Left (123) / Ctrl+Right (124): Space switching.
            let isSpaceSwitch = flags.contains(.control) && (code == 123 || code == 124)
            if isAppSwitch || isSpaceSwitch {
                Task { @MainActor in self?.close() }
            }
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        globalMonitor = nil
        localMonitor = nil
        keyMonitor = nil
        globalKeyMonitor = nil
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil
    }
}

private extension NSView {
    func findFirstTextField() -> NSTextField? {
        if let tf = self as? NSTextField { return tf }
        for sub in subviews {
            if let found = sub.findFirstTextField() { return found }
        }
        return nil
    }
}

final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
