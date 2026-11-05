import Foundation

/// Playback starts take precedence over an older session. Pausing retains the
/// same target so Play resumes the player the user was just listening to.
struct AutomaticPlayerResolver {
    private var previouslyPlaying: Set<PlaybackPlayer> = []
    private var lastPlayer: PlaybackPlayer?

    mutating func resolve(available: Set<PlaybackPlayer>, playing: Set<PlaybackPlayer>,
                          remembered: PlaybackPlayer?, foreground: PlaybackPlayer?) -> PlaybackPlayer? {
        let playing = playing.intersection(available)
        let started = playing.subtracting(previouslyPlaying)
        previouslyPlaying = playing

        func preferred(in candidates: Set<PlaybackPlayer>) -> PlaybackPlayer? {
            for player in [lastPlayer, remembered, foreground].compactMap({ $0 }) where candidates.contains(player) {
                return player
            }
            return PlaybackPlayer.allCases.first { candidates.contains($0) }
        }

        let retained = lastPlayer.flatMap { available.contains($0) ? $0 : nil }
        let selected = preferred(in: started) ?? retained ?? preferred(in: playing) ?? preferred(in: available)
        lastPlayer = selected
        return selected
    }
}
