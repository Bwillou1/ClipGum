import Foundation
import LlamaSwift

/// A small, local-only llama.cpp wrapper based on the official SwiftUI example
/// and SwiftLlama's actor/stream boundary. The C context never escapes it.
actor GGUFInferenceEngine: ManagedInferenceEngine {
    private var configuration: InferenceConfiguration
    private var model: LoadedGGUFModel?
    private var loadedIdentifier: String?

    init(configuration: InferenceConfiguration) {
        self.configuration = configuration
    }

    func loadModel(identifier: String) async throws {
        guard Self.isAppleSilicon else {
            throw InferenceEngineError.unsupportedArchitecture
        }
        guard
            let identifier = ModelIdentifier(rawValue: identifier),
            identifier.backend == .gguf,
            identifier.localURL.pathExtension.lowercased() == "gguf"
        else {
            throw InferenceEngineError.invalidIdentifier
        }
        let canonicalIdentifier = ModelIdentifier.gguf(file: identifier.localURL)
        if loadedIdentifier == canonicalIdentifier, model != nil {
            return
        }

        model = nil
        loadedIdentifier = nil
        do {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: identifier.localURL.path
            )
            guard
                let size = attributes[.size] as? NSNumber,
                size.int64Value > 0
            else {
                throw InferenceEngineError.invalidModel
            }
            guard size.int64Value <= configuration.maximumModelFileBytes else {
                throw InferenceEngineError.modelTooLarge
            }
            model = try LoadedGGUFModel.load(
                path: identifier.localURL.path,
                contextTokens: configuration.contextTokens
            )
            loadedIdentifier = canonicalIdentifier
        } catch let error as InferenceEngineError {
            throw error
        } catch {
            throw InferenceErrorClassifier.classify(error)
        }
    }

    func transform(
        prompt: String,
        input: String,
        maxTokens: Int
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let model else {
            throw InferenceEngineError.modelNotLoaded
        }
        guard prompt.utf8.count + input.utf8.count <= configuration.maximumInputUTF8Bytes else {
            throw InferenceEngineError.inputTooLarge
        }
        guard !prompt.unicodeScalars.contains(where: { $0.value == 0 }),
            !input.unicodeScalars.contains(where: { $0.value == 0 })
        else {
            throw InferenceEngineError.invalidInput
        }

        let boundedTokens = configuration.boundedTokens(maxTokens)
        let maximumOutputBytes = configuration.maximumOutputUTF8Bytes
        let temperature = configuration.temperature
        let contextBudget = min(model.contextTokens, configuration.contextTokens)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let renderedPrompt = try model.renderPrompt(instructions: prompt, input: input)
                    let tokens = try model.tokenize(renderedPrompt)
                    guard tokens.count + boundedTokens < contextBudget else {
                        throw InferenceEngineError.contextLimit
                    }
                    try model.begin(tokens: tokens, temperature: temperature)

                    var decoder = IncrementalUTF8Decoder()
                    var outputBytes = 0
                    for _ in 0..<boundedTokens {
                        try Task.checkCancellation()
                        guard let piece = try model.nextToken() else {
                            break
                        }
                        if let chunk = try decoder.append(piece) {
                            outputBytes += chunk.utf8.count
                            guard outputBytes <= maximumOutputBytes else {
                                throw InferenceEngineError.outputTooLarge
                            }
                            continuation.yield(chunk)
                        }
                    }
                    if let tail = try decoder.finish() {
                        outputBytes += tail.utf8.count
                        guard outputBytes <= maximumOutputBytes else {
                            throw InferenceEngineError.outputTooLarge
                        }
                        continuation.yield(tail)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func unloadModel() async throws {
        // Releasing this value frees batch, sampler, context, model, and backend.
        model = nil
        loadedIdentifier = nil
    }

    func updateConfiguration(_ configuration: InferenceConfiguration) async {
        self.configuration = configuration
    }

    private static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }
}

private final class LlamaBackendRuntime {
    init() {
        // llama.cpp otherwise logs globally to stderr. ClipGum never accepts a
        // third-party logger as a potential prompt/output side channel.
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }

    deinit {
        llama_backend_free()
        llama_log_set(nil, nil)
    }
}

private final class LoadedGGUFModel {
    let contextTokens: Int
    // Retained until after context/model teardown in deinit.
    private let runtime: LlamaBackendRuntime
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private var batch: llama_batch
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private var nextPosition = 0

    private init(
        runtime: LlamaBackendRuntime,
        model: OpaquePointer,
        context: OpaquePointer,
        vocab: OpaquePointer,
        batch: llama_batch,
        contextTokens: Int
    ) {
        self.runtime = runtime
        self.model = model
        self.context = context
        self.vocab = vocab
        self.batch = batch
        self.contextTokens = contextTokens
    }

    static func load(path: String, contextTokens: Int) throws -> LoadedGGUFModel {
        let runtime = LlamaBackendRuntime()
        var modelParameters = llama_model_default_params()
        modelParameters.n_gpu_layers = 999
        // b10549 replaces use_mmap/use_mlock with an explicit load mode.
        // mmap avoids wiring the whole model into non-pageable unified memory.
        modelParameters.load_mode = LLAMA_LOAD_MODE_MMAP

        guard let model = llama_model_load_from_file(path, modelParameters) else {
            throw InferenceEngineError.invalidModel
        }
        do {
            var contextParameters = llama_context_default_params()
            contextParameters.n_ctx = UInt32(contextTokens)
            contextParameters.n_batch = 1_024
            let threads = Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))
            contextParameters.n_threads = threads
            contextParameters.n_threads_batch = threads

            guard let context = llama_init_from_model(model, contextParameters) else {
                throw InferenceEngineError.outOfMemory
            }
            guard let vocab = llama_model_get_vocab(model) else {
                llama_free(context)
                throw InferenceEngineError.invalidModel
            }
            let batch = llama_batch_init(1_024, 0, 1)
            return LoadedGGUFModel(
                runtime: runtime,
                model: model,
                context: context,
                vocab: vocab,
                batch: batch,
                contextTokens: contextTokens
            )
        } catch {
            llama_model_free(model)
            throw error
        }
    }

    deinit {
        if let sampler {
            llama_sampler_free(sampler)
        }
        llama_batch_free(batch)
        llama_free(context)
        llama_model_free(model)
        // `runtime` is released after this body and calls llama_backend_free().
    }

    func renderPrompt(instructions: String, input: String) throws -> String {
        guard let template = llama_model_chat_template(model, nil) else {
            // Models without embedded templates get a conservative text fallback.
            // Evaluation should prefer an instruct GGUF with a native template.
            return "System:\n\(instructions)\n\nUser data:\n\(input)\n\nAssistant:\n"
        }

        return try "system".withCString { systemRole in
            try "user".withCString { userRole in
                try instructions.withCString { systemContent in
                    try input.withCString { userContent in
                        let messages = [
                            llama_chat_message(role: systemRole, content: systemContent),
                            llama_chat_message(role: userRole, content: userContent)
                        ]
                        return try messages.withUnsafeBufferPointer { buffer in
                            let required = llama_chat_apply_template(
                                template,
                                buffer.baseAddress,
                                2,
                                true,
                                nil,
                                0
                            )
                            guard required > 0, required < 1_000_000 else {
                                throw InferenceEngineError.generationFailed
                            }
                            var output = [CChar](repeating: 0, count: Int(required) + 1)
                            let written = llama_chat_apply_template(
                                template,
                                buffer.baseAddress,
                                2,
                                true,
                                &output,
                                required + 1
                            )
                            guard written > 0, written <= required else {
                                throw InferenceEngineError.generationFailed
                            }
                            let bytes = output.prefix(Int(written)).map { UInt8(bitPattern: $0) }
                            guard let rendered = String(bytes: bytes, encoding: .utf8) else {
                                throw InferenceEngineError.generationFailed
                            }
                            return rendered
                        }
                    }
                }
            }
        }
    }

    func tokenize(_ prompt: String) throws -> [llama_token] {
        let textLength = Int32(prompt.utf8.count)
        let required = llama_tokenize(vocab, prompt, textLength, nil, 0, true, false)
        let capacity = required < 0
            ? Int(-required)
            : max(1, prompt.utf8.count + 2)
        guard capacity > 0, capacity < contextTokens * 4 else {
            throw InferenceEngineError.contextLimit
        }

        var tokens = [llama_token](repeating: 0, count: capacity)
        let written = llama_tokenize(
            vocab,
            prompt,
            textLength,
            &tokens,
            Int32(capacity),
            true,
            false
        )
        guard written > 0 else {
            throw InferenceEngineError.contextLimit
        }
        return Array(tokens.prefix(Int(written)))
    }

    func begin(tokens: [llama_token], temperature: Float) throws {
        guard !tokens.isEmpty else {
            throw InferenceEngineError.contextLimit
        }
        if let sampler {
            llama_sampler_free(sampler)
        }
        guard let newSampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            sampler = nil
            throw InferenceEngineError.outOfMemory
        }
        sampler = newSampler
        llama_sampler_chain_add(newSampler, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(newSampler, llama_sampler_init_top_p(0.95, 1))
        llama_sampler_chain_add(newSampler, llama_sampler_init_temp(temperature))
        llama_sampler_chain_add(newSampler, llama_sampler_init_dist(1_234))

        llama_memory_clear(llama_get_memory(context), true)
        nextPosition = 0
        let promptBatchSize = 1_024
        for start in stride(from: 0, to: tokens.count, by: promptBatchSize) {
            clearBatch()
            let end = min(tokens.count, start + promptBatchSize)
            for index in start..<end {
                appendToBatch(
                    token: tokens[index],
                    position: index,
                    logits: index == tokens.count - 1
                )
            }
            guard llama_decode(context, batch) == 0 else {
                throw InferenceEngineError.generationFailed
            }
        }
        nextPosition = tokens.count
    }

    /// Returns raw token-piece bytes, or nil at end-of-generation.
    func nextToken() throws -> [UInt8]? {
        guard let sampler else {
            throw InferenceEngineError.generationFailed
        }
        let token = llama_sampler_sample(sampler, context, -1)
        if llama_vocab_is_eog(vocab, token) {
            return nil
        }
        let bytes = try tokenPiece(token)

        clearBatch()
        appendToBatch(token: token, position: nextPosition, logits: true)
        nextPosition += 1
        guard llama_decode(context, batch) == 0 else {
            throw InferenceEngineError.generationFailed
        }
        return bytes
    }

    private func tokenPiece(_ token: llama_token) throws -> [UInt8] {
        var capacity: Int32 = 32
        var buffer = [CChar](repeating: 0, count: Int(capacity))
        var written = llama_token_to_piece(vocab, token, &buffer, capacity, 0, false)
        if written < 0 {
            capacity = -written
            guard capacity > 0, capacity < 1_024 else {
                throw InferenceEngineError.generationFailed
            }
            buffer = [CChar](repeating: 0, count: Int(capacity))
            written = llama_token_to_piece(vocab, token, &buffer, capacity, 0, false)
        }
        guard written >= 0, written <= capacity else {
            throw InferenceEngineError.generationFailed
        }
        return buffer.prefix(Int(written)).map { UInt8(bitPattern: $0) }
    }

    private func clearBatch() {
        batch.n_tokens = 0
    }

    private func appendToBatch(token: llama_token, position: Int, logits: Bool) {
        let index = Int(batch.n_tokens)
        batch.token[index] = token
        batch.pos[index] = llama_pos(position)
        batch.n_seq_id[index] = 1
        batch.seq_id[index]![0] = 0
        batch.logits[index] = logits ? 1 : 0
        batch.n_tokens += 1
    }
}

private struct IncrementalUTF8Decoder {
    private var pending: [UInt8] = []

    mutating func append(_ bytes: [UInt8]) throws -> String? {
        pending.append(contentsOf: bytes)
        guard !pending.isEmpty else {
            return nil
        }
        if let decoded = String(bytes: pending, encoding: .utf8) {
            pending.removeAll(keepingCapacity: false)
            return decoded.isEmpty ? nil : decoded
        }
        // Valid multi-token sequences can include text plus a partial scalar.
        // Bound malformed output instead of decoding it with U+FFFD replacement.
        guard pending.count <= 64 else {
            throw InferenceEngineError.generationFailed
        }
        return nil
    }

    mutating func finish() throws -> String? {
        guard !pending.isEmpty else {
            return nil
        }
        guard let decoded = String(bytes: pending, encoding: .utf8) else {
            throw InferenceEngineError.generationFailed
        }
        pending.removeAll(keepingCapacity: false)
        return decoded.isEmpty ? nil : decoded
    }
}
