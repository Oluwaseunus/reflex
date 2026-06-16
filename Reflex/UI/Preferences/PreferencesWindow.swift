import SwiftUI

/// Main preferences window with tabbed interface
struct PreferencesWindow: View {
    @State private var selectedTab: PreferenceTab = .general

    enum PreferenceTab: String, CaseIterable {
        case general = "General"
        case shortcuts = "Shortcuts"
        case about = "About"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .shortcuts: return "keyboard"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPreferencesView()
                .tabItem {
                    Label(PreferenceTab.general.rawValue, systemImage: PreferenceTab.general.icon)
                }
                .tag(PreferenceTab.general)

            ShortcutsPreferencesView()
                .tabItem {
                    Label(PreferenceTab.shortcuts.rawValue, systemImage: PreferenceTab.shortcuts.icon)
                }
                .tag(PreferenceTab.shortcuts)

            AboutPreferencesView()
                .tabItem {
                    Label(PreferenceTab.about.rawValue, systemImage: PreferenceTab.about.icon)
                }
                .tag(PreferenceTab.about)
        }
        .frame(width: 500, height: 400)
    }
}

#if DEBUG
struct PreferencesWindow_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesWindow()
            .environmentObject(PreferencesManager.shared)
    }
}
#endif
