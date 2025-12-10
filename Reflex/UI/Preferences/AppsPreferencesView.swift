import SwiftUI

/// Apps preferences tab for managing favorite apps
struct AppsPreferencesView: View {
    @EnvironmentObject var preferences: PreferencesManager
    @EnvironmentObject var appDetector: MediaAppDetector

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Favorite Apps")
                    .font(.headline)
                Text("Select apps to appear in the quick switch menu")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Apps List
            List {
                // Installed apps section
                Section {
                    ForEach(installedApps) { app in
                        AppPreferenceRow(
                            app: app,
                            isFavorite: preferences.isFavorite(app.id),
                            onToggle: { isFavorite in
                                if isFavorite {
                                    preferences.addFavorite(app.id)
                                } else {
                                    preferences.removeFavorite(app.id)
                                }
                            }
                        )
                    }
                } header: {
                    Text("Installed (\(installedApps.count))")
                }

                // Not installed apps section
                if !notInstalledApps.isEmpty {
                    Section {
                        ForEach(notInstalledApps) { app in
                            HStack {
                                Image(systemName: app.icon ?? "app")
                                    .frame(width: 24)
                                    .foregroundColor(.secondary)
                                Text(app.name)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Not Installed")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } header: {
                        Text("Not Installed")
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            // Footer info
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Favorite apps appear first in the quick switch menu")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private var installedApps: [MediaApp] {
        appDetector.availableApps
            .filter { $0.isInstalled }
            .sorted { $0.name < $1.name }
    }

    private var notInstalledApps: [MediaApp] {
        appDetector.availableApps
            .filter { !$0.isInstalled }
            .sorted { $0.name < $1.name }
    }
}

/// Row view for an app in the preferences list
struct AppPreferenceRow: View {
    let app: MediaApp
    let isFavorite: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            // App icon
            Image(systemName: app.icon ?? "app")
                .frame(width: 24)
                .foregroundColor(.accentColor)

            // App name
            Text(app.name)

            Spacer()

            // Running indicator
            if app.isRunning {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .help("Currently running")
            }

            // Favorite toggle
            Toggle("", isOn: Binding(
                get: { isFavorite },
                set: { onToggle($0) }
            ))
            .labelsHidden()
        }
    }
}

#if DEBUG
struct AppsPreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        AppsPreferencesView()
            .environmentObject(PreferencesManager.shared)
            .environmentObject(MediaAppDetector())
            .frame(width: 500, height: 400)
    }
}
#endif
