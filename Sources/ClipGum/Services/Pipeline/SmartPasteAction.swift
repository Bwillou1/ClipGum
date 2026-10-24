import Foundation

enum SmartPasteAction: String, CaseIterable, Identifiable, Sendable {
    case clean
    case urlClean
    case secretScrub
    case shareReady
    case restoreIdentifiers
    case formatJSON
    case minifyJSON
    case jsonToTypeScript
    case scrubLogs
    case inspectBash
    case explainBash
    case correction
    case rewrite
    case tableToCSV

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: return "Clean + Redact"
        case .urlClean: return "URL Clean"
        case .secretScrub: return "Regex Secret Scrub"
        case .shareReady: return "Share-Ready"
        case .restoreIdentifiers: return "Restore Original Identifiers"
        case .formatJSON: return "JSON Pretty"
        case .minifyJSON: return "JSON Minify"
        case .jsonToTypeScript: return "JSON → TypeScript"
        case .scrubLogs: return "Log / Stack Trace Scrub"
        case .inspectBash: return "Bash Inspect (Never Executes)"
        case .explainBash: return "Bash Explain (Local LLM)"
        case .correction: return "Correction Only (Local LLM)"
        case .rewrite: return "Rewrite (Local LLM)"
        case .tableToCSV: return "Table to CSV (Local LLM)"
        }
    }

    var isMechanical: Bool {
        switch self {
        case .clean, .urlClean, .secretScrub, .shareReady, .restoreIdentifiers,
            .formatJSON, .minifyJSON, .jsonToTypeScript, .scrubLogs, .inspectBash:
            return true
        case .explainBash, .correction, .rewrite, .tableToCSV:
            return false
        }
    }
}

struct DeveloperActionOptions: Equatable, Sendable {
    var jsonIndentation: JSONIndentation = .twoSpaces
    var typeScriptRootName = "Root"
    var typeScriptIncludesExport = true
}
