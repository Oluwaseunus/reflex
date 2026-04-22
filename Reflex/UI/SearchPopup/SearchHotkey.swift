import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let openSpotifySearch = Self(
        "openSpotifySearch",
        default: .init(.s, modifiers: [.command, .option])
    )
}
