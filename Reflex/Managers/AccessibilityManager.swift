import Cocoa
import Combine

/// Manages Accessibility permissions required for CGEvent tap
final class AccessibilityManager: ObservableObject {
    static let shared = AccessibilityManager()

    /// Whether the app has Accessibility permission
    @Published private(set) var hasPermission: Bool = false

    /// Timer for polling permission status
    private var pollingTimer: Timer?

    private init() {
        // Check permission on init
        checkPermission()

        // Always poll for permission changes
        startPolling(interval: 1.0)
    }

    /// Check current Accessibility permission status
    @discardableResult
    func checkPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
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

    /// Test if we can actually create an event tap (more reliable than AXIsProcessTrusted)
    func canCreateEventTap() -> Bool {
        let mask: CGEventMask = (1 << 14) // NX_SYSDEFINED
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
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
            let wasGranted = self?.hasPermission ?? false
            self?.checkPermission()

            if let granted = self?.hasPermission, granted != wasGranted {
                NotificationCenter.default.post(
                    name: Constants.Notifications.permissionStatusChanged,
                    object: nil,
                    userInfo: ["granted": granted]
                )
            }
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
        stopPolling()
    }
}
