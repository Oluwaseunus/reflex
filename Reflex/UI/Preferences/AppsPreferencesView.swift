import SwiftUI

/// Apps preferences tab for managing favorite apps
struct AppsPreferencesView: View {
    @EnvironmentObject var preferences: PreferencesManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Media Apps (coming soon)")
                    .font(.headline)
                Text("Reflex currently targets Spotify only. Multi-app support will return later.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Placeholder explaining current scope
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Today Reflex routes media keys to Spotify. We’ll re-enable multi-app selection once core routing is stable.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
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
