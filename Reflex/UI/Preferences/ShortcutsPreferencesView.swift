import SwiftUI

/// Shortcuts preferences tab (placeholder for future feature)
struct ShortcutsPreferencesView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Custom Shortcuts")
                .font(.headline)

            Text("Custom keyboard shortcuts will be available in a future update.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Current shortcuts info
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Media Keys")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ShortcutRow(key: "F7 / ", action: "Previous Track")
                ShortcutRow(key: "F8 / ▶", action: "Play/Pause")
                ShortcutRow(key: "F9 / ", action: "Next Track")
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            Spacer()
        }
        .padding()
    }
}

/// Row showing a keyboard shortcut
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
