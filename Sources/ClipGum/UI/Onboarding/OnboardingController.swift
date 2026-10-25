import Foundation

enum OnboardingStep: Int, CaseIterable {
    case explicitTrigger = 1
    case permissions
    case modelReadiness
}

@MainActor
final class OnboardingController: ObservableObject {
    private enum Keys {
        static let completed = "phase5.onboarding.completed"
    }

    @Published private(set) var step: OnboardingStep = .explicitTrigger
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var isCompleted: Bool

    private let defaults: UserDefaults
    var onFinish: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isCompleted = defaults.bool(forKey: Keys.completed)
    }

    var isLastStep: Bool { step == .modelReadiness }
    var progressText: String { "Step \(step.rawValue) of \(OnboardingStep.allCases.count)" }

    func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
        if next == .permissions { refreshAccessibility() }
    }

    func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func refreshAccessibility() {
        accessibilityGranted = SystemPermissionCenter.accessibilityTrusted(prompt: false)
    }

    func requestAccessibility() {
        accessibilityGranted = SystemPermissionCenter.accessibilityTrusted(prompt: true)
    }

    func finish() {
        defaults.set(true, forKey: Keys.completed)
        isCompleted = true
        onFinish?()
    }
}
