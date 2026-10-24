import Foundation

/// Removes only well-known transport wrappers. It never rewrites model content
/// to make a failed semantic/schema validation pass.
struct OutputSanitizer {
    func sanitize(action: SmartPasteAction, source: String, output: String) -> String {
        var result = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)

        let prefixes: [String]
        switch action {
        case .explainBash:
            prefixes = ["Explanation:", "Bash explanation:", "Output:"]
        case .correction:
            prefixes = ["Corrected text:", "Correction:", "Output:"]
        case .rewrite:
            prefixes = ["Rewritten text:", "Rewrite:", "Output:"]
        case .tableToCSV:
            prefixes = ["CSV:", "Output:"]
        case .clean, .urlClean, .secretScrub, .shareReady, .restoreIdentifiers,
            .formatJSON, .minifyJSON, .jsonToTypeScript, .scrubLogs, .inspectBash:
            prefixes = []
        }
        for prefix in prefixes where result.lowercased().hasPrefix(prefix.lowercased())
            && !trimmedSource.lowercased().hasPrefix(prefix.lowercased())
        {
            let remainder = result.dropFirst(prefix.count)
            if !remainder.isEmpty {
                result = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            break
        }

        let sourceIsFencedBlock = trimmedSource.hasPrefix("```") && trimmedSource.hasSuffix("```")
        if !sourceIsFencedBlock,
            result.hasPrefix("```"),
            result.hasSuffix("```"),
            let firstNewline = result.firstIndex(of: "\n")
        {
            let contentStart = result.index(after: firstNewline)
            let contentEnd = result.index(result.endIndex, offsetBy: -3)
            if contentStart <= contentEnd {
                result = String(result[contentStart..<contentEnd])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        for prefix in prefixes where result.lowercased().hasPrefix(prefix.lowercased())
            && !trimmedSource.lowercased().hasPrefix(prefix.lowercased())
        {
            let remainder = result.dropFirst(prefix.count)
            if !remainder.isEmpty {
                result = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            break
        }
        return result
    }
}
