import SwiftUI

/// Brief, interruptible transitions for pointer feedback and first-run pages.
enum InterfaceMotion {
    static let hoverReveal = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.15)
    static let volumeReveal = Animation.spring(duration: 0.25, bounce: 0.2)
    static let onboardingPage = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.20)
}
