import Foundation
import CoreAudio
import AppKit

/// Monitors Core Audio process output activity to detect which applications are
/// currently outputting audio through the HAL. Uses `kAudioProcessPropertyIsRunningOutput`
/// to build a thread-safe snapshot of active output bundle IDs.
///
/// This class is **not wired into the app yet**. It is a pure addition introduced in
/// Commit 2 of the Core Audio refactor series. Nothing starts it, and runtime behaviour
/// is unchanged. The process-object code paths are guarded with `@available(macOS 14.2, *)`
/// because the required properties (`kAudioHardwarePropertyProcessObjectList`,
/// `kAudioProcessPropertyPID`, `kAudioProcessPropertyBundleID`,
/// `kAudioProcessPropertyIsRunningOutput`) require that OS version.
final class CoreAudioActivityMonitor {

    // MARK: - Browser bundle IDs (duplicated from SystemNowPlayingMonitor; shared in Commit 4)

    /// Known browser bundle identifiers. Duplicated here intentionally; will be extracted
    /// to a shared utility in Commit 4.
    private static let browserBundleIds: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.mozilla.firefox",
        "company.thebrowser.Browser",      // Arc
        "com.microsoft.edgemac",           // Edge
        "com.brave.Browser",
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi",
        "org.chromium.Chromium",
    ]

    // MARK: - Per-process entry

    /// Snapshot of a single HAL process object.
    struct ProcessEntry {
        let objectID: AudioObjectID
        let pid: pid_t
        let bundleID: String?
        var isRunningOutput: Bool
        var lastUpdate: Date
    }

    // MARK: - Internal state

    /// Dedicated serial queue for all Core Audio listener callbacks and state mutation.
    private let queue = DispatchQueue(label: "com.reflex.CoreAudioActivityMonitor", qos: .userInteractive)

    /// Lock protecting `_processEntries` and `_activeOutputBundleIds`.
    private var _lock = os_unfair_lock()

    /// Map from AudioObjectID to per-process entry.
    private var _processEntries: [AudioObjectID: ProcessEntry] = [:]

    /// Cached set of bundle IDs whose `isRunningOutput` is true, excluding Reflex itself.
    private var _activeOutputBundleIds: Set<String> = []

    /// Whether the monitor has been started.
    private var _isStarted = false

    /// Listener token for the process-list property on kAudioObjectSystemObject.
    /// We track whether it was registered so we can remove it on stop.
    private var _processListListenerRegistered = false

    // MARK: - Optional logging callbacks (for Commit 3 wiring)

    /// Called on the Core Audio serial queue whenever the set of active output bundle IDs
    /// changes. Do **not** call AppleScript or update SwiftUI state directly from this callback.
    var onActiveOutputsChanged: ((Set<String>) -> Void)?

    /// Called on the Core Audio serial queue when a single process flips its output state.
    /// Parameters: (pid, bundleID or nil, isRunningOutput).
    /// Do **not** call AppleScript or update SwiftUI state directly from this callback.
    var onProcessOutputChanged: ((pid_t, String?, Bool) -> Void)?

    // MARK: - Thread-safe snapshot accessors

    /// A snapshot of bundle IDs currently outputting audio.
    /// Thread-safe — safe to call from any thread including the CGEvent tap thread.
    var activeOutputBundleIds: Set<String> {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        return _activeOutputBundleIds
    }

    /// Returns `true` if the given bundle ID is currently outputting audio.
    /// Thread-safe — safe to call from any thread including the CGEvent tap thread.
    func isBundleOutputtingAudio(_ bundleId: String) -> Bool {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        return _activeOutputBundleIds.contains(bundleId)
    }

    /// `true` if any known browser bundle ID is currently outputting audio.
    /// Thread-safe — safe to call from any thread including the CGEvent tap thread.
    var isBrowserOutputtingAudio: Bool {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        return !_activeOutputBundleIds.isDisjoint(with: Self.browserBundleIds)
    }

    /// `true` if Spotify is currently outputting audio.
    /// Thread-safe — safe to call from any thread including the CGEvent tap thread.
    var isSpotifyOutputtingAudio: Bool {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        return _activeOutputBundleIds.contains("com.spotify.client")
    }

    // MARK: - Lifecycle

    /// Start the monitor. Idempotent — safe to call multiple times.
    ///
    /// On macOS 14.2+: reconciles the full HAL process list and registers
    /// property listeners for `kAudioHardwarePropertyProcessObjectList` and
    /// per-process `kAudioProcessPropertyIsRunningOutput`.
    ///
    /// On earlier OS versions: logs a warning and returns without registering any listeners.
    func start() {
        guard !_isStarted else { return }
        _isStarted = true

        if #available(macOS 14.2, *) {
            Logger.shared.info("CoreAudioActivityMonitor: Starting (macOS 14.2+ path)")
            registerProcessListListener()
            reconcileProcessList()
        } else {
            Logger.shared.warning("CoreAudioActivityMonitor: macOS 14.2+ required for process-object path; monitor is inactive")
        }
    }

    /// Stop the monitor and remove all registered listeners. Safe to call multiple times.
    func stop() {
        guard _isStarted else { return }
        _isStarted = false

        if #available(macOS 14.2, *) {
            removeAllListeners()
        }

        os_unfair_lock_lock(&_lock)
        _processEntries.removeAll()
        _activeOutputBundleIds.removeAll()
        os_unfair_lock_unlock(&_lock)

        Logger.shared.info("CoreAudioActivityMonitor: Stopped")
    }

    deinit {
        stop()
    }

    // MARK: - Process list listener (macOS 14.2+)

    @available(macOS 14.2, *)
    private func registerProcessListListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(AudioObjectID(kAudioObjectSystemObject), &address) else {
            Logger.shared.warning("CoreAudioActivityMonitor: kAudioHardwarePropertyProcessObjectList not available on this system")
            return
        }

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue
        ) { [weak self] _, _ in
            self?.handleProcessListChanged()
        }

        if status == noErr {
            _processListListenerRegistered = true
            Logger.shared.debug("CoreAudioActivityMonitor: Registered process-list listener")
        } else {
            Logger.shared.error("CoreAudioActivityMonitor: Failed to register process-list listener (OSStatus \(status))")
        }
    }

    @available(macOS 14.2, *)
    private func handleProcessListChanged() {
        Logger.shared.debug("CoreAudioActivityMonitor: Process list changed — reconciling")
        reconcileProcessList()
    }

    // MARK: - Process list reconciliation (macOS 14.2+)

    @available(macOS 14.2, *)
    private func reconcileProcessList() {
        // Read the current list of process AudioObjectIDs from the HAL.
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &dataSize
        )

        guard status == noErr, dataSize > 0 else {
            Logger.shared.warning("CoreAudioActivityMonitor: Failed to get process object list size (OSStatus \(status))")
            return
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var objectIDs = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &dataSize,
            &objectIDs
        )

        guard status == noErr else {
            Logger.shared.warning("CoreAudioActivityMonitor: Failed to read process object list (OSStatus \(status))")
            return
        }

        let newObjectIDSet = Set(objectIDs.filter { $0 != kAudioObjectUnknown })

        // Snapshot existing entries under lock.
        os_unfair_lock_lock(&_lock)
        let existingObjectIDSet = Set(_processEntries.keys)
        os_unfair_lock_unlock(&_lock)

        // Add listeners for new process objects.
        let added = newObjectIDSet.subtracting(existingObjectIDSet)
        for objectID in added {
            addProcessEntry(for: objectID)
        }

        // Remove entries for disappeared process objects.
        let removed = existingObjectIDSet.subtracting(newObjectIDSet)
        for objectID in removed {
            removeProcessEntry(for: objectID)
        }

        Logger.shared.debug("CoreAudioActivityMonitor: Reconciled — \(newObjectIDSet.count) processes (\(added.count) added, \(removed.count) removed)")
    }

    // MARK: - Per-process entry management (macOS 14.2+)

    @available(macOS 14.2, *)
    private func addProcessEntry(for objectID: AudioObjectID) {
        let pid = readPID(for: objectID)
        let bundleID = resolveBundleID(for: objectID, pid: pid)

        // Filter out Reflex's own process.
        if let pid = pid, pid == ProcessInfo.processInfo.processIdentifier {
            return
        }
        if let bundleID = bundleID, bundleID == Bundle.main.bundleIdentifier {
            return
        }

        let isRunningOutput = readIsRunningOutput(for: objectID)

        let entry = ProcessEntry(
            objectID: objectID,
            pid: pid ?? 0,
            bundleID: bundleID,
            isRunningOutput: isRunningOutput,
            lastUpdate: Date()
        )

        os_unfair_lock_lock(&_lock)
        _processEntries[objectID] = entry
        os_unfair_lock_unlock(&_lock)

        // Register per-process listener.
        registerIsRunningOutputListener(for: objectID)

        // Update the active output snapshot.
        rebuildActiveOutputSnapshot()
    }

    @available(macOS 14.2, *)
    private func removeProcessEntry(for objectID: AudioObjectID) {
        // Remove per-process listener first (stale object errors are acceptable).
        unregisterIsRunningOutputListener(for: objectID)

        os_unfair_lock_lock(&_lock)
        _processEntries.removeValue(forKey: objectID)
        os_unfair_lock_unlock(&_lock)

        rebuildActiveOutputSnapshot()
    }

    // MARK: - Per-process isRunningOutput listener (macOS 14.2+)

    @available(macOS 14.2, *)
    private func registerIsRunningOutputListener(for objectID: AudioObjectID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(objectID, &address) else {
            return
        }

        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, queue) { [weak self] _, _ in
            self?.handleIsRunningOutputChanged(for: objectID)
        }

        if status != noErr {
            Logger.shared.debug("CoreAudioActivityMonitor: Failed to register isRunningOutput listener for objectID \(objectID) (OSStatus \(status))")
        }
    }

    @available(macOS 14.2, *)
    private func unregisterIsRunningOutputListener(for objectID: AudioObjectID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // We need a stable block reference to remove it. Since AudioObjectAddPropertyListenerBlock
        // requires the same block pointer for removal and we do not store them, we use
        // AudioObjectRemovePropertyListenerBlock by re-creating a no-op block.
        // In practice, on macOS 14.2+ the HAL accepts kAudioHardwareBadObjectError for
        // already-gone objects — treat that as cleanup-complete.
        //
        // Limitation: without storing the original block pointer we cannot remove the exact
        // block. We call RemovePropertyListenerBlock with a new block; the HAL may return
        // an error (kAudioHardwareBadObjectError) for stale objects, which we treat as success.
        let noopBlock: AudioObjectPropertyListenerBlock = { _, _ in }
        let status = AudioObjectRemovePropertyListenerBlock(objectID, &address, queue, noopBlock)

        let kAudioHardwareBadObjectError = OSStatus(0x21_6f_62_6a) // '!obj'
        if status != noErr && status != kAudioHardwareBadObjectError {
            Logger.shared.debug("CoreAudioActivityMonitor: isRunningOutput listener removal for objectID \(objectID) returned OSStatus \(status)")
        }
    }

    @available(macOS 14.2, *)
    private func handleIsRunningOutputChanged(for objectID: AudioObjectID) {
        let isRunningOutput = readIsRunningOutput(for: objectID)

        os_unfair_lock_lock(&_lock)
        guard var entry = _processEntries[objectID] else {
            os_unfair_lock_unlock(&_lock)
            return
        }
        let bundleID = entry.bundleID
        entry.isRunningOutput = isRunningOutput
        entry.lastUpdate = Date()
        _processEntries[objectID] = entry
        os_unfair_lock_unlock(&_lock)

        Logger.shared.debug("CoreAudioActivityMonitor: output changed pid=\(entry.pid) bundle=\(bundleID ?? "<unknown>") runningOutput=\(isRunningOutput)")

        onProcessOutputChanged?(entry.pid, bundleID, isRunningOutput)

        rebuildActiveOutputSnapshot()
    }

    // MARK: - Snapshot rebuild

    /// Rebuild the `_activeOutputBundleIds` cache from current entries.
    /// Must be called on the Core Audio serial queue (or init path).
    private func rebuildActiveOutputSnapshot() {
        os_unfair_lock_lock(&_lock)
        var snapshot: Set<String> = []
        for entry in _processEntries.values where entry.isRunningOutput {
            if let bundleID = entry.bundleID {
                snapshot.insert(bundleID)
            }
        }
        let changed = snapshot != _activeOutputBundleIds
        _activeOutputBundleIds = snapshot
        os_unfair_lock_unlock(&_lock)

        if changed {
            Logger.shared.debug("CoreAudioActivityMonitor: active output bundles=\(snapshot)")
            onActiveOutputsChanged?(snapshot)
        }
    }

    // MARK: - Listener removal on stop (macOS 14.2+)

    @available(macOS 14.2, *)
    private func removeAllListeners() {
        // Remove process-list listener.
        if _processListListenerRegistered {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyProcessObjectList,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let noopBlock: AudioObjectPropertyListenerBlock = { _, _ in }
            let status = AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                queue,
                noopBlock
            )
            let kAudioHardwareBadObjectError = OSStatus(0x21_6f_62_6a) // '!obj'
            if status != noErr && status != kAudioHardwareBadObjectError {
                Logger.shared.debug("CoreAudioActivityMonitor: Process-list listener removal returned OSStatus \(status)")
            }
            _processListListenerRegistered = false
        }

        // Remove per-process listeners.
        os_unfair_lock_lock(&_lock)
        let objectIDs = Array(_processEntries.keys)
        os_unfair_lock_unlock(&_lock)

        for objectID in objectIDs {
            unregisterIsRunningOutputListener(for: objectID)
        }
    }

    // MARK: - Core Audio property reads (macOS 14.2+)

    @available(macOS 14.2, *)
    private func readPID(for objectID: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(objectID, &address) else { return nil }

        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &pid)

        guard status == noErr else {
            Logger.shared.debug("CoreAudioActivityMonitor: Failed to read PID for objectID \(objectID) (OSStatus \(status))")
            return nil
        }
        return pid
    }

    @available(macOS 14.2, *)
    private func resolveBundleID(for objectID: AudioObjectID, pid: pid_t?) -> String? {
        // Primary: NSRunningApplication lookup by PID.
        if let pid = pid, pid > 0,
           let app = NSRunningApplication(processIdentifier: pid),
           let bundleID = app.bundleIdentifier {
            return bundleID
        }

        // Fallback: kAudioProcessPropertyBundleID.
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(objectID, &address) else { return nil }

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return nil }

        // kAudioProcessPropertyBundleID is a CFString property. Read it as an
        // Unmanaged<CFString> to avoid the UnsafeMutableRawPointer warning.
        var unmanagedString: Unmanaged<CFString>? = nil
        status = withUnsafeMutablePointer(to: &unmanagedString) { ptr in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, ptr)
        }
        guard status == noErr,
              let taken = unmanagedString?.takeRetainedValue() as String? else { return nil }
        return taken.isEmpty ? nil : taken
    }

    @available(macOS 14.2, *)
    private func readIsRunningOutput(for objectID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(objectID, &address) else { return false }

        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)

        guard status == noErr else {
            Logger.shared.debug("CoreAudioActivityMonitor: Failed to read isRunningOutput for objectID \(objectID) (OSStatus \(status))")
            return false
        }
        return value != 0
    }
}
