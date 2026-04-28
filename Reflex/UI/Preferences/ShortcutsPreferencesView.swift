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

            VStack(alignment: .leading, spacing: 8) {
                Text("Current Media Keys")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ShortcutRow(key: "F7 / ⏮", action: "Previous Track")
                ShortcutRow(key: "F8 / ▶", action: "Play/Pause")
                ShortcutRow(key: "F9 / ⏭", action: "Next Track")
            }
            .padding()
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)

            Spacer()
        }
        .padding()
    }
}

struct ShortcutRow: View {
    let key: String
    let action: String

    var body: some View {
        HStack {
            Text(key)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)

            Spacer()

            Text(action)
                .foregroundColor(.secondary)
        }
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
