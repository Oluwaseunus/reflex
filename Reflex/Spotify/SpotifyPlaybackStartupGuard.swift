import Foundation
import os

/// Shared guard for the fragile window immediately after dispatching Spotify
/// playback startup. During this window Spotify is rebuilding its player
/// and some AppleScript reads can observe or perturb an incomplete track state.
enum SpotifyPlaybackStartupGuard {
    static let quietPeriod: TimeInterval = 6.0

    struct SuppressionToken {
        fileprivate let generation: UInt64
    }

    private static var lock = os_unfair_lock()
    private static var suppressReadsUntil: Date = .distantPast
    private static var generation: UInt64 = 0

    @discardableResult
    static func suppressReadsForStartup() -> SuppressionToken {
        suppressReads(for: quietPeriod)
    }

    @discardableResult
    static func suppressReads(for interval: TimeInterval) -> SuppressionToken {
        let until = Date().addingTimeInterval(interval)
        os_unfair_lock_lock(&lock)
        generation &+= 1
        let token = SuppressionToken(generation: generation)
        if until > suppressReadsUntil {
            suppressReadsUntil = until
        }
        os_unfair_lock_unlock(&lock)
        return token
    }

    static func clearSuppression(_ token: SuppressionToken) {
        os_unfair_lock_lock(&lock)
        if token.generation == generation {
            suppressReadsUntil = .distantPast
        }
        os_unfair_lock_unlock(&lock)
    }

    static var isSuppressingReads: Bool {
        let now = Date()
        os_unfair_lock_lock(&lock)
        if now >= suppressReadsUntil {
            suppressReadsUntil = .distantPast
            os_unfair_lock_unlock(&lock)
            return false
        }
        os_unfair_lock_unlock(&lock)
        return true
    }
}
