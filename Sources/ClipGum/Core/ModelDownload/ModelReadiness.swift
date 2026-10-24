import Foundation

struct ModelReadiness: Equatable, Sendable {
    let isAppleSilicon: Bool
    let unifiedRAMBytes: UInt64
    let requiredRAMBytes: UInt64

    static let gibibyte: UInt64 = 1_073_741_824

    static func current(requiredRAMBytes: UInt64 = 0) -> ModelReadiness {
        #if arch(arm64)
        let appleSilicon = true
        #else
        let appleSilicon = false
        #endif
        return ModelReadiness(
            isAppleSilicon: appleSilicon,
            unifiedRAMBytes: UInt64(ProcessInfo.processInfo.physicalMemory),
            requiredRAMBytes: requiredRAMBytes
        )
    }

    var canLoadModel: Bool {
        isAppleSilicon && unifiedRAMBytes >= requiredRAMBytes
    }

    var summary: String {
        guard isAppleSilicon else {
            return "Apple Silicon is required for local MLX and GGUF inference."
        }
        let memory = ByteCountFormatter.string(
            fromByteCount: Int64(min(unifiedRAMBytes, UInt64(Int64.max))),
            countStyle: .memory
        )
        if unifiedRAMBytes < requiredRAMBytes {
            return "This model requires more than \(memory) unified memory. Choose a smaller verified model."
        }
        if unifiedRAMBytes < 8 * Self.gibibyte {
            return "Apple Silicon · \(memory) unified memory · use a small quantized model."
        }
        if unifiedRAMBytes < 16 * Self.gibibyte {
            return "Apple Silicon · \(memory) unified memory · model size remains workload-dependent."
        }
        return "Apple Silicon · \(memory) unified memory · ready for verified local weights."
    }
}
