import Foundation

/// Shared browser bundle ID classifier used by both `SystemNowPlayingMonitor`
/// and `CoreAudioActivityMonitor` for browser coexistence detection.
enum BrowserBundleIDs {

    /// Known browser bundle identifiers.
    static let browserBundleIds: Set<String> = [
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

    /// Returns `true` if the given bundle ID belongs to a known browser.
    static func isBrowser(_ bundleId: String) -> Bool {
        browserBundleIds.contains(bundleId)
    }
}
