import Foundation

enum SmartPasteAction: String, CaseIterable, Identifiable, Sendable {
    case clean
    case urlClean
    case secretScrub
    case formatJSON
    case correction
    case rewrite
    case tableToCSV

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: return "Clean + Redact"
        case .urlClean: return "URL Clean"
        case .secretScrub: return "Regex Secret Scrub"
        case .formatJSON: return "JSON Format"
        case .correction: return "Correction Only (Local LLM)"
        case .rewrite: return "Rewrite (Local LLM)"
        case .tableToCSV: return "Table to CSV (Local LLM)"
        }
    }

    var isMechanical: Bool {
        switch self {
        case .clean, .urlClean, .secretScrub, .formatJSON:
            return true
        case .correction, .rewrite, .tableToCSV:
            return false
        }
    }
}
