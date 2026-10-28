import Foundation

enum SpotifyForegroundPolicy {
    // Device menus may activate Reflex after a refresh captures the previous
    // app. Permit that process explicitly without accepting any other app.
    static func accepts(expected: pid_t?, current: pid_t?, reflex: pid_t? = nil) -> Bool {
        guard let expected else { return true }
        guard let current else { return false }
        return current == expected || current == reflex
    }
}
