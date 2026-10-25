import Combine
import Foundation

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

    @Published var huggingFaceRepo: String {
        didSet { defaults.set(huggingFaceRepo, forKey: hfRepoKey) }
    }
    @Published var apiEndpoint: String {
        didSet { defaults.set(apiEndpoint, forKey: apiEndpointKey) }
    }
    @Published var apiModelName: String {
        didSet { defaults.set(apiModelName, forKey: apiModelKey) }
    }
    @Published var apiKey: String {
        didSet { defaults.set(apiKey, forKey: apiKeyKey) }
    }

    var onChange: ((InferenceConfiguration) -> Void)?
    var onLoadModel: ((String) -> Void)?

    private let defaults: UserDefaults
    private let temperatureKey = "phase2.inference.temperature"
    private let tokensKey = "phase2.inference.maximumOutputTokens"
    private let idleKey = "phase2.inference.idleUnloadMinutes"
    private let hfRepoKey = "phase2.inference.huggingFaceRepo"
    private let apiEndpointKey = "phase2.inference.apiEndpoint"
    private let apiModelKey = "phase2.inference.apiModelName"
    private let apiKeyKey = "phase2.inference.apiKey"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedTemperature = defaults.object(forKey: temperatureKey) as? Double ?? 0.2
        let storedTokens = defaults.object(forKey: tokensKey) as? Int ?? 256
        let storedIdle = defaults.object(forKey: idleKey) as? Double ?? 5
        let storedHfRepo = defaults.string(forKey: hfRepoKey) ?? ModelIdentifier.defaultHuggingFaceRepo
        let storedEndpoint = defaults.string(forKey: apiEndpointKey) ?? "http://localhost:11434/v1"
        let storedModel = defaults.string(forKey: apiModelKey) ?? "llama3"
        let storedKey = defaults.string(forKey: apiKeyKey) ?? ""

        temperature = min(0.3, max(0.1, storedTemperature))
        maximumOutputTokens = min(512, max(64, storedTokens))
        idleUnloadMinutes = min(60, max(1, storedIdle))
        huggingFaceRepo = storedHfRepo
        apiEndpoint = storedEndpoint
        apiModelName = storedModel
        apiKey = storedKey
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
