import SwiftUI

enum SettingsPane: String, CaseIterable {
    case general = "General"
    case permissions = "Permissions"
    case shortcuts = "Shortcuts"
    case about = "About"

    var icon: String {
        switch self {
        case .general: return "gear"
        case .permissions: return "lock.shield"
        case .shortcuts: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

final class SettingsNavigationModel: ObservableObject {
    @Published var selectedPane: SettingsPane {
        didSet {
            defaults.set(selectedPane.rawValue, forKey: Constants.UserDefaultsKeys.lastSettingsPane)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedPane = defaults.string(forKey: Constants.UserDefaultsKeys.lastSettingsPane)
            .flatMap(SettingsPane.init(rawValue:)) ?? .general
    }
}

/// Content for the pane selected in the native Settings toolbar.
struct PreferencesWindow: View {
    @ObservedObject var navigation: SettingsNavigationModel

    var body: some View {
        Group {
            switch navigation.selectedPane {
            case .general:
                GeneralPreferencesView()
            case .permissions:
                PermissionsPreferencesView()
            case .shortcuts:
                ShortcutsPreferencesView()
            case .about:
                AboutPreferencesView()
            }
        }
        .frame(width: 520, height: 420)
    }
}

#if DEBUG
struct PreferencesWindow_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesWindow(navigation: SettingsNavigationModel())
            .environmentObject(PreferencesManager.shared)
    }
}
#endif
