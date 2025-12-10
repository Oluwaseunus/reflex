import SwiftUI

/// Permissions guide step during onboarding
struct PermissionsGuideView: View {
    @StateObject private var accessibilityManager = AccessibilityManager.shared
    @State private var isPolling = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 16) {
                // Icon changes based on permission state
                Image(systemName: accessibilityManager.hasPermission ?
                      "checkmark.shield.fill" : "lock.shield")
                    .font(.system(size: 60))
                    .foregroundColor(accessibilityManager.hasPermission ? .green : .orange)
                    .animation(.easeInOut, value: accessibilityManager.hasPermission)

                Text("Accessibility Permission")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Reflex needs Accessibility permission to intercept media keys")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)

            // Permission granted state
            if accessibilityManager.hasPermission {
                permissionGrantedView
            } else {
                permissionRequiredView
            }

            Spacer()
        }
        .padding()
        .onAppear {
            accessibilityManager.checkPermission()
        }
        .onDisappear {
            accessibilityManager.stopPolling()
        }
    }

    private var permissionGrantedView: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Permission Granted!")
                    .font(.headline)
                    .foregroundColor(.green)
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)

            Text("Media key interception is now enabled")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var permissionRequiredView: some View {
        VStack(spacing: 20) {
            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                InstructionRow(number: 1, text: "Click 'Open System Settings' below")
                InstructionRow(number: 2, text: "Find Reflex in the list")
                InstructionRow(number: 3, text: "Toggle the switch to enable")
                InstructionRow(number: 4, text: "Return to this window")
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)

            // Open button
            Button(action: openSystemPreferences) {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Open System Settings")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Why needed info
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reflex uses Accessibility permission to:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    BulletPoint(text: "Intercept media key presses (Play/Pause, Next, Previous)")
                    BulletPoint(text: "Route commands to your chosen media app")
                    BulletPoint(text: "Prevent default system handling when desired")

                    Text("Your privacy is protected - Reflex only monitors media keys and doesn't access any other input.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .padding()
            } label: {
                Text("Why is this needed?")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
        }
    }

    private func openSystemPreferences() {
        accessibilityManager.openSystemPreferences()
        accessibilityManager.startPolling()
    }
}

/// Instruction row with number
struct InstructionRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor)
                .clipShape(Circle())

            Text(text)
                .font(.subheadline)
        }
    }
}

/// Bullet point text
struct BulletPoint: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#if DEBUG
struct PermissionsGuideView_Previews: PreviewProvider {
    static var previews: some View {
        PermissionsGuideView()
            .frame(width: 600, height: 500)
    }
}
#endif
