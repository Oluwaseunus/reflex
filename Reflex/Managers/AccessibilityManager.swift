import Cocoa
import Combine

/// Manages Accessibility permissions required for CGEvent tap
final class AccessibilityManager: ObservableObject {
    static let shared = AccessibilityManager()

    /// Whether the app has Accessibility permission
    @Published private(set) var hasPermission: Bool = false

    /// Timer for polling permission status
    private var pollingTimer: Timer?

    /// Cached result of canCreateEventTap(), checked once at init
    private var cachedEventTapResult: Bool = false

    private init() {
        // Check event tap capability once; it only changes on permission grant
        cachedEventTapResult = canCreateEventTap()

        // Check permission on init
        checkPermission()

        // Listen for permission changes from within the app
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePermissionChange(_:)),
            name: Constants.Notifications.permissionStatusChanged,
            object: nil
        )

        // Always poll for permission changes (uses lightweight AXIsProcessTrusted)
        startPolling(interval: Constants.Timing.permissionCheckInterval)
    }

    @objc private func handlePermissionChange(_ notification: Notification) {
        if let granted = notification.userInfo?["granted"] as? Bool, granted {
            // Permission was granted — refresh the cached event tap result
            cachedEventTapResult = canCreateEventTap()
        }
    }

    /// Check current Accessibility permission status
    @discardableResult
    func checkPermission() -> Bool {
        let axTrusted = AXIsProcessTrusted()
        // Only probe event tap when AXIsProcessTrusted is false (ad-hoc signed builds).
        // canCreateEventTap() is heavyweight (creates/destroys a kernel event tap),
        // so we avoid calling it on every poll cycle.
        if !axTrusted && !cachedEventTapResult {
            cachedEventTapResult = canCreateEventTap()
        }
        let trusted = axTrusted || cachedEventTapResult
        let changed = trusted != hasPermission
        hasPermission = trusted

        if changed {
            Logger.shared.permission("Accessibility permission changed: \(hasPermission ? "granted" : "denied")")
            if trusted {
                // Permission was just granted, notify
                NotificationCenter.default.post(
                    name: Constants.Notifications.permissionStatusChanged,
                    object: nil,
                    userInfo: ["granted": true]
                )
            }
        }
        return hasPermission
    }

    /// Test if we can actually create an event tap (more reliable than AXIsProcessTrusted
    /// for ad-hoc signed builds where AXIsProcessTrusted can return false despite having permission)
    func canCreateEventTap() -> Bool {
        let mask: CGEventMask = (1 << 14) // NX_SYSDEFINED
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) {
            // Clean up the test tap
            CGEvent.tapEnable(tap: tap, enable: false)
            return true
        }
        return false
    }

    /// Request Accessibility permission (shows system prompt)
    func requestPermission() {
        Logger.shared.permission("Requesting Accessibility permission")

        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true
        ]
        let result = AXIsProcessTrustedWithOptions(options)

        if !result {
            Logger.shared.permissionDenied("Accessibility")
        }

        hasPermission = result
    }

    /// Open System Preferences to Accessibility pane
    func openSystemPreferences() {
        Logger.shared.permission("Opening System Preferences -> Accessibility")

        if let url = URL(string: Constants.URLs.accessibilityPreferences) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Start polling for permission changes
    func startPolling(interval: TimeInterval = Constants.Timing.permissionCheckInterval) {
        stopPolling()

        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkPermission()
        }

        Logger.shared.permission("Started permission polling (interval: \(interval)s)")
    }

    /// Stop polling for permission changes
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        Logger.shared.permission("Stopped permission polling")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopPolling()
    }
}
