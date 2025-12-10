import SwiftUI

/// About tab showing app information
struct AboutPreferencesView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // App Icon
            Image(systemName: "music.note.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            // App Name and Version
            Text("Reflex")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Version \(Constants.App.version)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Description
            Text("Intelligent media key routing for macOS")
                .font(.body)
                .foregroundColor(.secondary)

            Spacer()

            // Features
            VStack(alignment: .leading, spacing: 8) {
                FeatureRow(icon: "play.circle", text: "Route media keys to your preferred apps")
                FeatureRow(icon: "arrow.triangle.swap", text: "Smart auto-switching between playing apps")
                FeatureRow(icon: "music.note.list", text: "Support for Spotify, Apple Music, VLC, and more")
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)

            Spacer()

            // Links
            HStack(spacing: 20) {
                Button("GitHub") {
                    if let url = URL(string: "https://github.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Text("•")
                    .foregroundColor(.secondary)

                Button("Report Issue") {
                    if let url = URL(string: "https://github.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .font(.caption)

            // Copyright
            Text("Made with ❤️")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }
}

/// Row showing a feature with icon
struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.accentColor)
            Text(text)
                .font(.subheadline)
        }
    }
}

#if DEBUG
struct AboutPreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        AboutPreferencesView()
            .frame(width: 500, height: 400)
    }
}
#endif
