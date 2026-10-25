import Foundation

/// HTTP OpenAI-compatible backend for local engines (Ollama, LM Studio, vLLM) or remote endpoints.
actor APIInferenceEngine: ManagedInferenceEngine {
    private var configuration: InferenceConfiguration
    private var endpointURL: URL?
    private var modelName: String = "default"
    private var apiKey: String?
    private var loadedIdentifier: String?
    private let session: URLSession

    init(configuration: InferenceConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func loadModel(identifier: String) async throws {
        guard let modelID = ModelIdentifier(rawValue: identifier),
              modelID.backend == .api,
              let url = modelID.endpointURL else {
            throw InferenceEngineError.invalidIdentifier
        }
        self.endpointURL = url
        self.modelName = modelID.repoOrModelName ?? "default"
        self.apiKey = modelID.apiKey
        self.loadedIdentifier = identifier
    }

    func unloadModel() async throws {
        endpointURL = nil
        loadedIdentifier = nil
    }

    func updateConfiguration(_ configuration: InferenceConfiguration) async {
        self.configuration = configuration
    }

    func transform(
        prompt: String,
        input: String,
        maxTokens: Int
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let baseURL = endpointURL else {
            throw InferenceEngineError.modelNotLoaded
        }
        guard prompt.utf8.count + input.utf8.count <= configuration.maximumInputUTF8Bytes else {
            throw InferenceEngineError.inputTooLarge
        }

        var targetURL = baseURL
        if !targetURL.path.contains("chat/completions") {
            if targetURL.path.hasSuffix("/v1") || targetURL.path.hasSuffix("/v1/") {
                targetURL = targetURL.appendingPathComponent("chat/completions")
            } else {
                targetURL = targetURL.appendingPathComponent("v1/chat/completions")
            }
        }

        var request = URLRequest(url: targetURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let boundedTokens = configuration.boundedTokens(maxTokens)
        let payload: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": input]
            ],
            "temperature": configuration.temperature,
            "max_tokens": boundedTokens,
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        return AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                        continuation.finish(throwing: InferenceEngineError.generationFailed)
                        return
                    }

                    var emittedBytes = 0
                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }
                        if trimmed == "data: [DONE]" { break }

                        if trimmed.hasPrefix("data: ") {
                            let jsonString = String(trimmed.dropFirst(6))
                            if let data = jsonString.data(using: .utf8),
                               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = root["choices"] as? [[String: Any]],
                               let first = choices.first {
                                if let delta = first["delta"] as? [String: Any],
                                   let content = delta["content"] as? String {
                                    emittedBytes += content.utf8.count
                                    if emittedBytes > configuration.maximumOutputUTF8Bytes {
                                        continuation.finish(throwing: InferenceEngineError.outputTooLarge)
                                        return
                                    }
                                    continuation.yield(content)
                                } else if let message = first["message"] as? [String: Any],
                                          let content = message["content"] as? String {
                                    continuation.yield(content)
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: InferenceErrorClassifier.classify(error))
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
