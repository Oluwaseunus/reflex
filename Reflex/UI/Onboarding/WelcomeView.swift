import SwiftUI
import AppKit

/// Main onboarding flow shown on first launch
struct WelcomeView: View {
    @State private var currentStep: OnboardingStep = .welcome
    @State private var animateStepChange = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            ZStack {
                stepContent
                    .id(currentStep)
                    .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.97)))
            }
            .frame(maxHeight: .infinity)
            .animation(animateStepChange ? InterfaceMotion.onboardingPage : nil, value: currentStep)

            Divider()

            // Navigation
            navigationBar
        }
        .frame(width: 600, height: 600)
    }

    private var navigationBar: some View {
        HStack {
            // Back button
            Button("Back") {
                changeStep(by: -1)
            }
            .frame(width: 90, alignment: .leading)
            .opacity(currentStep == .welcome ? 0 : 1)
            .disabled(currentStep == .welcome)
            .accessibilityHidden(currentStep == .welcome)

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
            Button(currentStep == .complete ? "Get Started" : "Next") {
                if currentStep == .complete {
                    completeOnboarding()
                } else {
                    changeStep(by: 1)
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(width: 90, alignment: .trailing)
        }
        .padding()
    }

    @ViewBuilder
    private var stepContent: some View {
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

    private func changeStep(by offset: Int) {
        guard let next = OnboardingStep(rawValue: currentStep.rawValue + offset) else { return }
        // Keyboard navigation stays immediate, even on this rare first-run flow.
        let eventType = NSApp.currentEvent?.type
        animateStepChange = eventType == .leftMouseUp || eventType == .leftMouseDown
        currentStep = next
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
                    description: "Type a song and press Return to play it in Spotify"
                )
                OnboardingFeatureRow(
                    icon: "timer",
                    title: "Sleep Timer",
                    description: "Type > in search to find sleep timer commands"
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

                Text("Keep Spotify installed and signed in. Allow Reflex in Accessibility for background search, and allow Automation when macOS asks to control Spotify.")
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
                Text("Click the menu bar icon to switch between apps or open Settings")
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
