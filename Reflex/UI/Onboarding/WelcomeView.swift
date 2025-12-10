import SwiftUI

/// Main onboarding flow shown on first launch
struct WelcomeView: View {
    @State private var currentStep: OnboardingStep = .welcome
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject var preferences: PreferencesManager
    @EnvironmentObject var appDetector: MediaAppDetector

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
                    PermissionsGuideView()
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
        .frame(width: 600, height: 560)
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
            Text("Intelligent media key routing for macOS")
                .font(.title3)
                .foregroundColor(.secondary)

            Spacer()

            // Features
            VStack(alignment: .leading, spacing: 16) {
                OnboardingFeatureRow(
                    icon: "play.circle",
                    title: "Smart Routing",
                    description: "Route media keys to your favorite apps"
                )
                OnboardingFeatureRow(
                    icon: "arrow.triangle.swap",
                    title: "Auto-Switching",
                    description: "Automatically detect which app is playing"
                )
                OnboardingFeatureRow(
                    icon: "music.note.list",
                    title: "Multi-App Support",
                    description: "Works with Spotify, Apple Music, VLC, and more"
                )
            }
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
    @EnvironmentObject var preferences: PreferencesManager
    @EnvironmentObject var appDetector: MediaAppDetector

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("Select Your Favorite Apps")
                    .font(.title)
                    .fontWeight(.bold)

                Text("These will appear in your quick switch menu")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 24)

            // Apps list
            List {
                ForEach(appDetector.installedApps) { app in
                    HStack {
                        Image(systemName: app.icon ?? "app")
                            .frame(width: 24)
                            .foregroundColor(.accentColor)

                        Text(app.name)

                        Spacer()

                        if app.isRunning {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                        }

                        Toggle("", isOn: Binding(
                            get: { preferences.isFavorite(app.id) },
                            set: { isFavorite in
                                if isFavorite {
                                    preferences.addFavorite(app.id)
                                } else {
                                    preferences.removeFavorite(app.id)
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(maxHeight: 250)

            // Info
            if appDetector.installedApps.isEmpty {
                Text("No supported media apps found. You can add more later.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

/// Completion step
struct CompletionStepView: View {
    @ObservedObject var accessibilityManager = AccessibilityManager.shared

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
                    title: "Accessibility Permission",
                    isComplete: accessibilityManager.hasPermission
                )

                StatusRow(
                    title: "Menu Bar Icon",
                    isComplete: true
                )

                StatusRow(
                    title: "Media Key Interception",
                    isComplete: accessibilityManager.hasPermission
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
