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
        if loadedIdentifier == ModelIdentifier.mlx(directory: identifier.localURL), container != nil {
            return
        }

        unloadModelResources()
        let directory = identifier.localURL
        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
            isDirectory.boolValue,
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
