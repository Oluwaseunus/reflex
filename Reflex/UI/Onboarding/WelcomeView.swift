import SwiftUI

/// Main onboarding flow shown on first launch
struct WelcomeView: View {
    @State private var currentStep: OnboardingStep = .welcome
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject var preferences: PreferencesManager

    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case permissions = 1
        case selectApps = 2
        case complete = 3
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content
            Group {
                switch currentStep {
                case .welcome:
                    WelcomeStepView()
                case .permissions:
                    AutomationPermissionStepView()
                case .selectApps:
                    AppSelectionStepView()
                case .complete:
                    CompletionStepView()
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            // Navigation
            navigationBar
        }
        .frame(width: 600, height: 600)
    }

    private var navigationBar: some View {
        HStack {
            // Back button
            if currentStep != .welcome {
                Button("Back") {
                    withAnimation {
                        if let previous = OnboardingStep(rawValue: currentStep.rawValue - 1) {
                            currentStep = previous
                        }
                    }
                }
            }

            // Progress indicators
            Spacer()
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            Spacer()

            // Next/Finish button
            if currentStep == .complete {
                Button("Get Started") {
                    completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Next") {
                    withAnimation {
                        if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
                            currentStep = next
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private func completeOnboarding() {
        preferences.completeOnboarding()
        dismiss()
        Logger.shared.info("Onboarding completed")
    }
}

/// Welcome step - introduces the app
struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon
            Image(systemName: "music.note.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)

            // Title
            Text("Welcome to Reflex")
                .font(.largeTitle)
                .fontWeight(.bold)

            // Subtitle
            Text("Spotify controls from your menu bar")
                .font(.title3)
                .foregroundColor(.secondary)

            Spacer()

            // Features
            VStack(alignment: .leading, spacing: 16) {
                OnboardingFeatureRow(
                    icon: "play.circle",
                    title: "Playback Controls",
                    description: "Control Spotify without leaving the current app"
                )
                OnboardingFeatureRow(
                    icon: "sparkle.magnifyingglass",
                    title: "Quick Search",
                    description: "Find tracks, albums, and artists with a global shortcut"
                )
                OnboardingFeatureRow(
                    icon: "music.note.list",
                    title: "Queue Access",
                    description: "View upcoming Spotify tracks from the menu bar"
                )
            }
            .padding(.horizontal, 60)

            Spacer()
        }
        .padding()
    }
}

/// Automation permission step during onboarding
struct AutomationPermissionStepView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundColor(.accentColor)

            VStack(spacing: 8) {
                Text("Automation Access")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Reflex needs permission to control Spotify and read current playback context.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 50)

            AutomationPermissionControls()
                .padding(.horizontal, 60)

            Spacer()
        }
        .padding()
    }
}

/// Feature row for onboarding
struct OnboardingFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// App selection step during onboarding
struct AppSelectionStepView: View {
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("Spotify First")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Reflex currently focuses on Spotify playback, search, and queue controls. Multi-app selection will return later.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 24)

            Spacer()

            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Spotify")
                        .font(.headline)
                    Text("Enabled for playback, search, and queue controls")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal, 60)

            Spacer()
        }
        .padding()
    }
}

/// Completion step
struct CompletionStepView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Reflex will run in your menu bar")
                .font(.title3)
                .foregroundColor(.secondary)

            Spacer()

            // Status summary
            VStack(spacing: 12) {
                StatusRow(
                    title: "Menu Bar App",
                    isComplete: true
                )

                StatusRow(
                    title: "Spotify Controls",
                    isComplete: true
                )

                StatusRow(
                    title: "Search Shortcut",
                    isComplete: true
                )
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)

            // Tip
            HStack {
                Image(systemName: "lightbulb")
                    .foregroundColor(.yellow)
                Text("Click the menu bar icon to switch between apps or access preferences")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            Spacer()
        }
        .padding()
    }
}

/// Status row for completion screen
struct StatusRow: View {
    let title: String
    let isComplete: Bool

    var body: some View {
        HStack {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isComplete ? .green : .red)

            Text(title)

            Spacer()

            Text(isComplete ? "Ready" : "Needs Setup")
                .font(.caption)
                .foregroundColor(isComplete ? .green : .red)
        }
    }
}

#if DEBUG
struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView()
            .environmentObject(PreferencesManager.shared)
            .environmentObject(MediaAppDetector())
    }
}
#endif
