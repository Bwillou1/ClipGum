import Combine
import Foundation

/// Persists resource preferences only—never model paths, prompts, or clipboard data.
@MainActor
final class InferencePreferences: ObservableObject {
    @Published var temperature: Double {
        didSet { persistAndNotify() }
    }
    @Published var maximumOutputTokens: Int {
        didSet { persistAndNotify() }
    }
    @Published var idleUnloadMinutes: Double {
        didSet { persistAndNotify() }
    }

    var onChange: ((InferenceConfiguration) -> Void)?

    private let defaults: UserDefaults
    private let temperatureKey = "phase2.inference.temperature"
    private let tokensKey = "phase2.inference.maximumOutputTokens"
    private let idleKey = "phase2.inference.idleUnloadMinutes"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedTemperature = defaults.object(forKey: temperatureKey) as? Double ?? 0.2
        let storedTokens = defaults.object(forKey: tokensKey) as? Int ?? 256
        let storedIdle = defaults.object(forKey: idleKey) as? Double ?? 5
        temperature = min(0.3, max(0.1, storedTemperature))
        maximumOutputTokens = min(512, max(64, storedTokens))
        idleUnloadMinutes = min(60, max(1, storedIdle))
    }

    var configuration: InferenceConfiguration {
        InferenceConfiguration(
            temperature: Float(temperature),
            maximumOutputTokens: maximumOutputTokens,
            idleUnloadTimeout: idleUnloadMinutes * 60
        )
    }

    private func persistAndNotify() {
        defaults.set(temperature, forKey: temperatureKey)
        defaults.set(maximumOutputTokens, forKey: tokensKey)
        defaults.set(idleUnloadMinutes, forKey: idleKey)
        onChange?(configuration)
    }
}
