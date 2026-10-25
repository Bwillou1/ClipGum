import ClipGumCore
import CoreML
import Foundation

public enum MobileInferenceError: LocalizedError {
    case modelTooLarge
    case invalidInput
    case unsupportedOutput
    case thermalFallback

    public var errorDescription: String? {
        switch self {
        case .modelTooLarge: return "The local model exceeds the 500 MiB mobile budget."
        case .invalidInput: return "The mobile inference input is outside its bounded text profile."
        case .unsupportedOutput: return "The local model did not return bounded text."
        case .thermalFallback: return "Thermal pressure selected deterministic cleaning instead."
        }
    }
}

/// CoreML-only, local-model adapter. It does not download weights or infer a
/// remote endpoint. A host app chooses the model URL explicitly.
@available(iOS 17.0, *)
public final class CoreMLTextInference {
    public static let maximumModelBytes = 500 * 1_024 * 1_024
    public static let maximumInputBytes = 1 * 1_024 * 1_024
    public static let maximumOutputBytes = 2 * 1_024 * 1_024

    private let model: MLModel
    private let inputFeature: String
    private let outputFeature: String

    public init(modelURL: URL, inputFeature: String = "text", outputFeature: String = "output") throws {
        let values = try modelURL.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size <= Self.maximumModelBytes else {
            throw MobileInferenceError.modelTooLarge
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        model = try MLModel(contentsOf: modelURL, configuration: configuration)
        self.inputFeature = inputFeature
        self.outputFeature = outputFeature
    }

    public func transform(_ input: String) async throws -> String {
        guard input.utf8.count <= Self.maximumInputBytes else { throw MobileInferenceError.invalidInput }
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            throw MobileInferenceError.thermalFallback
        default:
            break
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            inputFeature: MLFeatureValue(string: input)
        ])
        let prediction = try model.prediction(from: provider)
        guard let output = prediction.featureValue(for: outputFeature)?.stringValue,
              output.utf8.count <= Self.maximumOutputBytes else {
            throw MobileInferenceError.unsupportedOutput
        }
        return output
    }
}

@available(iOS 17.0, *)
public struct MobileInferenceCoordinator {
    private let cleaner = MobileCleaningService()

    public init() {}

    /// The fallback is always deterministic and local. Both model input and
    /// output cross the deterministic boundary; no raw clipboard/share payload
    /// is supplied to a model. Oversized input fails instead of allocating an
    /// unbounded fallback workload.
    public func transform(_ input: String, using model: CoreMLTextInference?) async throws -> String {
        guard input.utf8.count <= CoreMLTextInference.maximumInputBytes else {
            throw MobileInferenceError.invalidInput
        }
        let cleanedInput = cleaner.clean(input).output
        guard let model, !Self.thermalPressureRequiresFallback else {
            return cleanedInput
        }
        do {
            let output = try await model.transform(cleanedInput)
            return cleaner.clean(output).output
        } catch {
            return cleanedInput
        }
    }

    private static var thermalPressureRequiresFallback: Bool {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            return true
        default:
            return false
        }
    }
}
