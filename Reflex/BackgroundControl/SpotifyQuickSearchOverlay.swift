import ApplicationServices

/// The modal Quick Search hides the main player from Spotify's AX tree.
/// A search field alone is not sufficient evidence to send Escape.
enum SpotifyQuickSearchOverlay {
    static func matches(
        groupLabel: String,
        descendantRoles: Set<String>,
        descendantLabels: Set<String>,
        mainPlayerExposed: Bool = false
    ) -> Bool {
        guard !mainPlayerExposed, groupLabel == "Search",
              descendantRoles.contains(kAXComboBoxRole) else { return false }
        // With no query, Quick Search exposes only its field and wrappers.
        let emptyOverlay = descendantRoles.isSubset(of: [kAXGroupRole, kAXComboBoxRole])
        let populatedOverlay = descendantRoles.contains(kAXListRole)
            && Set(["Navigate", "Enter", "Open", "Shift", "Play"]).isSubset(of: descendantLabels)
        return emptyOverlay || populatedOverlay
    }
}
