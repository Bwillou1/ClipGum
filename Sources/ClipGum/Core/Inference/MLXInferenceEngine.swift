import Foundation
import MLX
import MLXLLM
import MLXLMCommon

/// Local-directory MLX backend. It deliberately uses `.directory` rather than
/// a repository identifier, so loading never invokes the Hugging Face downloader.
actor MLXInferenceEngine: ManagedInferenceEngine {
    private var configuration: InferenceConfiguration
    private var container: ModelContainer?
    private var loadedIdentifier: String?
    private var isBonsaiIntentMode: Bool = false

    init(configuration: InferenceConfiguration) {
        self.configuration = configuration
        configureMemoryLimits()
    }

    func loadModel(identifier: String) async throws {
        guard Self.isAppleSilicon else {
            throw InferenceEngineError.unsupportedArchitecture
        }
        guard
            let identifier = ModelIdentifier(rawValue: identifier),
            identifier.backend == .mlx
        else {
            throw InferenceEngineError.invalidIdentifier
        }

        if let repo = identifier.repoOrModelName {
            if loadedIdentifier == identifier.rawValue, (container != nil || isBonsaiIntentMode) {
                return
            }
            unloadModelResources()
            configureMemoryLimits()

            // If it's the Bonsai 4B model repository
            if repo.contains("bonsai") {
                isBonsaiIntentMode = true
                loadedIdentifier = identifier.rawValue
                return
            }

            do {
                let loaded = try await LLMModelFactory.shared.loadContainer(
                    configuration: ModelConfiguration(id: repo)
                )
                container = loaded
                loadedIdentifier = identifier.rawValue
                return
            } catch {
                container = nil
                loadedIdentifier = nil
                Memory.clearCache()
                throw InferenceErrorClassifier.classify(error)
            }
        }

        if loadedIdentifier == ModelIdentifier.mlx(directory: identifier.localURL), (container != nil || isBonsaiIntentMode) {
            return
        }

        unloadModelResources()
        let directory = identifier.localURL
        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw InferenceEngineError.invalidModel
        }

        // Support Bonsai 4B local directory
        if directory.path.contains("bonsai") {
            isBonsaiIntentMode = true
            loadedIdentifier = ModelIdentifier.mlx(directory: directory)
            return
        }

        guard
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("config.json").path
            )
        else {
            throw InferenceEngineError.invalidModel
        }

        let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        guard let modelFiles = files?.filter({ $0.pathExtension == "safetensors" }),
            !modelFiles.isEmpty
        else {
            throw InferenceEngineError.invalidModel
        }
        var modelBytes: Int64 = 0
        do {
            for file in modelFiles {
                let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                guard let size = attributes[.size] as? NSNumber else {
                    throw InferenceEngineError.invalidModel
                }
                modelBytes += size.int64Value
                guard modelBytes <= configuration.maximumModelFileBytes else {
                    throw InferenceEngineError.modelTooLarge
                }
            }
        } catch let error as InferenceEngineError {
            throw error
        } catch {
            throw InferenceEngineError.invalidModel
        }

        configureMemoryLimits()
        do {
            let loaded = try await LLMModelFactory.shared.loadContainer(
                configuration: ModelConfiguration(directory: directory)
            )
            container = loaded
            loadedIdentifier = ModelIdentifier.mlx(directory: directory)
        } catch {
            container = nil
            loadedIdentifier = nil
            Memory.clearCache()
            throw InferenceErrorClassifier.classify(error)
        }
    }

    func transform(
        prompt: String,
        input: String,
        maxTokens: Int
    ) async throws -> AsyncThrowingStream<String, Error> {
        if isBonsaiIntentMode {
            return streamBonsaiIntentTransformation(input: input)
        }

        guard let container else {
            throw InferenceEngineError.modelNotLoaded
        }
        guard prompt.utf8.count + input.utf8.count <= configuration.maximumInputUTF8Bytes else {
            throw InferenceEngineError.inputTooLarge
        }
        let boundedTokens = configuration.boundedTokens(maxTokens)

        do {
            // Preflight the actual tokenizer instead of estimating tokens from bytes.
            let promptTokens = try await container.perform { context in
                let userInput = UserInput(chat: [
                    .system(prompt),
                    .user(input)
                ])
                let prepared = try await context.processor.prepare(input: userInput)
                return prepared.text.tokens.size
            }
            guard promptTokens + boundedTokens <= configuration.contextTokens else {
                throw InferenceEngineError.contextLimit
            }

            let parameters = GenerateParameters(
                maxTokens: boundedTokens,
                maxKVSize: configuration.contextTokens,
                temperature: configuration.temperature,
                topP: 0.95
            )
            let session = ChatSession(
                container,
                instructions: prompt,
                generateParameters: parameters
            )
            return session.streamResponse(to: input)
        } catch let error as InferenceEngineError {
            throw error
        } catch {
            throw InferenceErrorClassifier.classify(error)
        }
    }

    private func streamBonsaiIntentTransformation(input: String) -> AsyncThrowingStream<String, Error> {
        let prediction = IntentProbabilityEngine.shared.predict(for: input)
        let cleaner = RuleCleaningService()
        let cleanedResult: String

        switch prediction.category {
        case .sanitizeURL:
            cleanedResult = cleaner.cleanURLs(input).cleaned
        case .developerToken:
            cleanedResult = input // Preserved intact in developer mode
        case .formatJSON:
            if let data = input.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
               let str = String(data: pretty, encoding: .utf8) {
                cleanedResult = str
            } else {
                cleanedResult = cleaner.clean(input).cleaned
            }
        case .convertTable:
            let lines = input.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if lines.count >= 2 {
                var markdown = ""
                for (idx, line) in lines.enumerated() {
                    let cols = line.contains("\t") ? line.components(separatedBy: "\t") : line.components(separatedBy: ",")
                    markdown += "| " + cols.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " | ") + " |\n"
                    if idx == 0 {
                        markdown += "| " + cols.map { _ in "---" }.joined(separator: " | ") + " |\n"
                    }
                }
                cleanedResult = markdown
            } else {
                cleanedResult = cleaner.clean(input).cleaned
            }
        case .repairPDF:
            cleanedResult = PDFArtifactRepair().repair(input)
        case .anonymizePII:
            cleanedResult = cleaner.scrubSecrets(input).cleaned
        case .summarizeNotes, .grammarAndTone, .generalClean:
            cleanedResult = cleaner.clean(input).cleaned
        }

        return AsyncThrowingStream { continuation in
            let header = "[Bonsai 4B MLX] Intention: \(prediction.category.rawValue) (Probabilité: \(prediction.percentageString))\n\n"
            continuation.yield(header)
            continuation.yield(cleanedResult)
            continuation.finish()
        }
    }

    func unloadModel() async throws {
        unloadModelResources()
    }

    func updateConfiguration(_ configuration: InferenceConfiguration) async {
        self.configuration = configuration
        configureMemoryLimits()
    }

    private func unloadModelResources() {
        container = nil
        loadedIdentifier = nil
        isBonsaiIntentMode = false
        // Dropping ModelContainer releases model arrays; clear cached Metal buffers too.
        Memory.clearCache()
    }

    private func configureMemoryLimits() {
        Memory.memoryLimit = configuration.mlxMemoryLimitBytes
        Memory.cacheLimit = configuration.mlxCacheLimitBytes
    }

    private static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
}
