import SwiftUI
import KeyboardShortcuts

struct ShortcutsPreferencesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Custom Shortcuts")
                    .font(.headline)
                Text("Rebind Reflex's global shortcuts below.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Spotify Search")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .openSpotifySearch)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)

            Spacer()
        }
        .padding()
    }
}

#if DEBUG
struct ShortcutsPreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        ShortcutsPreferencesView()
            .frame(width: 500, height: 400)
    }
}
#endif
