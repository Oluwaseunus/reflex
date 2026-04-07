import Cocoa
import Carbon

// NX_SYSDEFINED event type (14) for system-defined events including media keys
private let NX_SYSDEFINED: Int64 = 14

/// Intercepts global media key presses using CGEvent tap
final class MediaKeyListener {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Synchronous callback to decide whether to swallow a media key event.
    /// Called on the CGEvent tap thread. Must be fast and thread-safe (no AppleScript).
    /// Return true to consume (swallow), false to pass through to the system.
    var shouldConsumeMediaKey: ((MediaCommand) -> Bool)?

    /// Async callback to execute the action after the swallow decision is made.
    /// Called on the main thread.
    var onMediaKeyPressed: ((MediaCommand) -> Void)?

    /// Whether the listener is currently active
    private(set) var isListening: Bool = false

    /// Tracks key codes whose key-down was consumed, so we also swallow their key-up
    var consumedKeys: Set<Int> = []

    /// Timestamp of last play/pause to debounce held-key repeats
    var lastPlayPauseTime: TimeInterval = 0

    /// Start listening for media key events
    @discardableResult
    func startListening() -> Bool {
        guard !isListening else {
            Logger.shared.warning("MediaKeyListener already listening")
            return true
        }

        // Don't check AccessibilityManager.hasPermission - just try to create the tap
        // AXIsProcessTrusted() can return false even when we have permission for adhoc-signed apps
        Logger.shared.info("Attempting to create event tap...")

        // Create event tap for system-defined events (which include media keys)
        // NX_SYSDEFINED = 14 is the event type for system-defined events
        let eventMask: CGEventMask = (1 << NX_SYSDEFINED)

        // Use a wrapper struct to pass self to the C callback
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: mediaKeyEventCallback,
            userInfo: refcon
        ) else {
            Logger.shared.error("Failed to create CGEvent tap. Check Accessibility permissions.")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        guard let source = runLoopSource else {
            Logger.shared.error("Failed to create run loop source")
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isListening = true
        Logger.shared.info("Media key listener started")
        return true
    }

    /// Stop listening for media key events
    func stopListening() {
        guard isListening else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isListening = false

        Logger.shared.info("Media key listener stopped")
    }

    /// Re-enable the event tap if it was disabled by the system
    func reEnableTapIfNeeded() {
        guard let tap = eventTap else { return }

        if !CGEvent.tapIsEnabled(tap: tap) {
            Logger.shared.warning("Event tap was disabled, re-enabling...")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    deinit {
        stopListening()
    }
}

/// C callback function for CGEvent tap
private func mediaKeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else {
        return Unmanaged.passRetained(event)
    }

    let listener = Unmanaged<MediaKeyListener>.fromOpaque(refcon).takeUnretainedValue()

    // Handle tap disabled event
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        Logger.shared.warning("Event tap disabled (type: \(type.rawValue)), attempting to re-enable")
        DispatchQueue.main.async {
            listener.reEnableTapIfNeeded()
        }
        return Unmanaged.passRetained(event)
    }

    // Only process system-defined events (type 14 = NX_SYSDEFINED)
    guard type.rawValue == UInt32(NX_SYSDEFINED) else {
        return Unmanaged.passRetained(event)
    }

    // Check if this is a media key event (subtype 8)
    let nsEvent = NSEvent(cgEvent: event)
    guard let subtype = nsEvent?.subtype, subtype.rawValue == 8 else {
        return Unmanaged.passRetained(event)
    }

    // This IS a media key event - parse it
    return parseMediaKeyEvent(event: event, listener: listener)
}

/// Parse media key event from CGEvent data.
/// Conditionally swallows media key events based on the shouldConsumeMediaKey callback,
/// and dispatches the action asynchronously on the main thread.
private func parseMediaKeyEvent(event: CGEvent, listener: MediaKeyListener) -> Unmanaged<CGEvent>? {
    let data1 = event.getIntegerValueField(CGEventField(rawValue: 38)!)
    let keyCode = Int((data1 & 0xFFFF0000) >> 16)
    let keyFlags = Int((data1 & 0x0000FF00) >> 8)

    // Map to a command, or pass through if not a media key we handle
    let command: MediaCommand
    switch keyCode {
    case Constants.MediaKeyCodes.play: command = .playPause
    case Constants.MediaKeyCodes.next: command = .nextTrack
    case Constants.MediaKeyCodes.previous: command = .previousTrack
    default:
        return Unmanaged.passRetained(event)
    }

    // Detect key-down vs key-up
    let isKeyDown = (keyFlags & 0x08) != 0 && (keyFlags & 0x01) == 0
    let isKeyUp = (keyFlags & 0x08) != 0 && (keyFlags & 0x01) != 0

    if isKeyDown {
        // Debounce play/pause to prevent rapid toggling from held-key repeats
        if command == .playPause {
            let now = ProcessInfo.processInfo.systemUptime
            if now - listener.lastPlayPauseTime < 0.4 {
                return nil // swallow debounced repeat
            }
            listener.lastPlayPauseTime = now
        }

        // Ask whether to consume this key (synchronous, thread-safe)
        let shouldConsume = listener.shouldConsumeMediaKey?(command) ?? true

        if shouldConsume {
            // Track that we consumed this key-down so we also swallow its key-up
            listener.consumedKeys.insert(keyCode)

            Logger.shared.event("Media key captured: \(command.displayName)")

            // Fire the action asynchronously on the main thread
            DispatchQueue.main.async {
                listener.onMediaKeyPressed?(command)
            }

            return nil // swallow
        } else {
            Logger.shared.event("Media key passed through: \(command.displayName)")
            return Unmanaged.passRetained(event) // pass through to system
        }
    }

    if isKeyUp {
        // If we consumed the matching key-down, also consume key-up
        if listener.consumedKeys.remove(keyCode) != nil {
            return nil // swallow key-up
        } else {
            return Unmanaged.passRetained(event) // pass through key-up
        }
    }

    // Neither key-down nor key-up — pass through
    return Unmanaged.passRetained(event)
}
