import Cocoa
import Carbon

// NX_SYSDEFINED event type (14) for system-defined events including media keys
private let NX_SYSDEFINED: Int64 = 14

/// Intercepts global media key presses using CGEvent tap
final class MediaKeyListener {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Callback when a media key is pressed
    /// Return true to consume the event, false to let it pass through
    var onMediaKeyPressed: ((MediaCommand) -> Bool)?

    /// Whether the listener is currently active
    private(set) var isListening: Bool = false

    /// Start listening for media key events
    func startListening() {
        guard !isListening else {
            Logger.shared.warning("MediaKeyListener already listening")
            return
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
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        guard let source = runLoopSource else {
            Logger.shared.error("Failed to create run loop source")
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isListening = true
        Logger.shared.info("Media key listener started")
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
        Logger.shared.warning("Event tap disabled, attempting to re-enable")
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
    // NSEvent.EventSubtype.screenChanged has raw value 8, same as media keys
    let nsEvent = NSEvent(cgEvent: event)
    guard let subtype = nsEvent?.subtype, subtype.rawValue == 8 else {
        // Not a media key event, pass through
        return Unmanaged.passRetained(event)
    }

    // This IS a media key event - parse it
    return parseMediaKeyEvent(event: event, listener: listener)
}

/// Parse media key event from CGEvent data
/// SIMPLE LOGIC: Always capture media keys and route to the target media app
private func parseMediaKeyEvent(event: CGEvent, listener: MediaKeyListener) -> Unmanaged<CGEvent>? {
    // Get the raw event data
    // For system-defined events, the key info is stored in data1
    // CGEventField 38 corresponds to kCGEventData1
    let data1 = event.getIntegerValueField(CGEventField(rawValue: 38)!)

    // Extract key code and flags from data1
    // Format: ((keyCode << 16) | (keyFlags << 8))
    let keyCode = Int((data1 & 0xFFFF0000) >> 16)
    let keyFlags = Int((data1 & 0x0000FF00) >> 8)

    // Check if this is a key down event
    let keyDown = (keyFlags & 0x0A) == 0x0A

    // Pass through key-up events
    guard keyDown else {
        return Unmanaged.passRetained(event)
    }

    // Map key code to MediaCommand
    let command: MediaCommand?
    switch keyCode {
    case Constants.MediaKeyCodes.play:
        command = .playPause
    case Constants.MediaKeyCodes.next:
        command = .nextTrack
    case Constants.MediaKeyCodes.previous:
        command = .previousTrack
    default:
        command = nil
    }

    // Not a media key we handle, pass through
    guard let command = command else {
        return Unmanaged.passRetained(event)
    }

    // ALWAYS capture and route to our target media app
    Logger.shared.event("Media key captured: \(command.displayName)")

    // Ask the router whether to consume this key
    var shouldConsume = false
    if let handler = listener.onMediaKeyPressed {
        // Ensure routing happens on the main thread to avoid reentrancy issues with NSAppleScript
        if Thread.isMainThread {
            shouldConsume = handler(command)
        } else {
            DispatchQueue.main.sync {
                shouldConsume = handler(command)
            }
        }
    }

    // Consume only when handler says so; otherwise let the system/browser receive it
    return shouldConsume ? nil : Unmanaged.passRetained(event)
}
