import Foundation

/// Monitors the system's "Now Playing" app via the private MRMediaRemote framework.
/// Polls periodically and caches the result for synchronous, thread-safe access
/// from the CGEvent tap callback thread.
final class SystemNowPlayingMonitor {

    /// Known browser bundle identifiers
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

    // MARK: - Thread-safe cached state

    /// The bundle identifier of the app macOS currently considers "now playing",
    /// excluding Reflex itself. Accessed from the CGEvent tap thread — must be thread-safe.
    private var _nowPlayingBundleId: String?
    private var _lock = os_unfair_lock()

    /// Thread-safe getter for the cached now-playing bundle ID.
    var nowPlayingBundleId: String? {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        return _nowPlayingBundleId
    }

    /// Thread-safe setter.
    private func setNowPlayingBundleId(_ bundleId: String?) {
        os_unfair_lock_lock(&_lock)
        _nowPlayingBundleId = bundleId
        os_unfair_lock_unlock(&_lock)
    }

    /// Whether the current system "now playing" app is a browser.
    /// Thread-safe — reads from cached state.
    var isBrowserNowPlaying: Bool {
        guard let bundleId = nowPlayingBundleId else { return false }
        return Self.browserBundleIds.contains(bundleId)
    }

    // MARK: - Reflex-filtering state (main thread only)

    /// Most recent non-Reflex bundle ID seen as now-playing.
    private var lastNonReflexBundleId: String?
    /// Timestamp of the most recent non-Reflex observation.
    private var lastNonReflexTimestamp: Date?
    /// If we haven't seen a non-Reflex app in this long, assume no browser is playing.
    private let stalenessThreshold: TimeInterval = 15.0

    // MARK: - MRMediaRemote function pointer

    private typealias MRMediaRemoteGetNowPlayingInfoFunction =
        @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void

    private var getNowPlayingInfo: MRMediaRemoteGetNowPlayingInfoFunction?
    private var pollingTimer: Timer?
    private var isMonitoring = false

    // MARK: - Lifecycle

    init() {
        loadFramework()
    }

    /// Dynamically load MediaRemote.framework and resolve the function pointer.
    private func loadFramework() {
        guard let bundle = CFBundleCreate(
            kCFAllocatorDefault,
            NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        ) else {
            Logger.shared.error("SystemNowPlayingMonitor: Failed to load MediaRemote.framework")
            return
        }

        guard let pointer = CFBundleGetFunctionPointerForName(
            bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString
        ) else {
            Logger.shared.error("SystemNowPlayingMonitor: Failed to resolve MRMediaRemoteGetNowPlayingInfo")
            return
        }

        getNowPlayingInfo = unsafeBitCast(pointer, to: MRMediaRemoteGetNowPlayingInfoFunction.self)
        Logger.shared.info("SystemNowPlayingMonitor: MediaRemote.framework loaded")
    }

    /// Start periodic polling for the system now-playing app.
    func startMonitoring(interval: TimeInterval = 2.0) {
        guard !isMonitoring else { return }
        guard getNowPlayingInfo != nil else {
            Logger.shared.warning("SystemNowPlayingMonitor: Cannot start — framework not loaded")
            return
        }

        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        isMonitoring = true

        // Immediate first poll
        poll()

        Logger.shared.info("SystemNowPlayingMonitor: Started polling (interval: \(interval)s)")
    }

    /// Stop polling.
    func stopMonitoring() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        isMonitoring = false
        Logger.shared.info("SystemNowPlayingMonitor: Stopped polling")
    }

    /// Perform a single poll of the system now-playing info.
    private func poll() {
        guard let getNowPlayingInfo = getNowPlayingInfo else { return }

        getNowPlayingInfo(DispatchQueue.main) { [weak self] info in
            guard let self = self else { return }

            let bundleId = info["kMRMediaRemoteNowPlayingInfoBundleIdentifier"] as? String
            let reflexBundleId = Bundle.main.bundleIdentifier

            if let bundleId = bundleId, bundleId != reflexBundleId {
                // A real app (not Reflex) is now-playing
                self.setNowPlayingBundleId(bundleId)
                self.lastNonReflexBundleId = bundleId
                self.lastNonReflexTimestamp = Date()
                Logger.shared.debug("SystemNowPlayingMonitor: Now playing = \(bundleId)")
            } else {
                // Reflex (or nothing) is now-playing.
                // Use the cached non-Reflex ID if it's recent enough.
                if let lastId = self.lastNonReflexBundleId,
                   let lastTime = self.lastNonReflexTimestamp,
                   Date().timeIntervalSince(lastTime) < self.stalenessThreshold {
                    self.setNowPlayingBundleId(lastId)
                } else {
                    self.setNowPlayingBundleId(nil)
                    self.lastNonReflexBundleId = nil
                }
            }
        }
    }

    deinit {
        stopMonitoring()
    }
}
