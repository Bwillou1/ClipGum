import Foundation

enum SmartPasteAction: String, CaseIterable, Identifiable, Sendable {
    case clean
    case repairPDF
    case sanitizeRichText
    case urlClean
    case secretScrub
    case shareReady
    case restoreIdentifiers
    case convertTable
    case formatJSON
    case minifyJSON
    case jsonToTypeScript
    case scrubLogs
    case inspectBash
    case explainBash
    case correction
    case professionalEmail
    case rewrite
    case slackSummary
    case tableToCSV

    var id: String { rawValue }

    var isFrench: Bool {
        Locale.preferredLanguages.first?.hasPrefix("fr") ?? true
    }

    var title: String {
        if isFrench {
            return frenchTitle
        }
        switch self {
        case .clean: return "Clean Plain Text + Redact"
        case .repairPDF: return "PDF Line-Wrap Repair"
        case .sanitizeRichText: return "Rich Text Sanitizer"
        case .urlClean: return "URL Clean"
        case .secretScrub: return "Regex Secret Scrub"
        case .shareReady: return "Share-Ready"
        case .restoreIdentifiers: return "Restore Original Identifiers"
        case .convertTable: return "Table Convert (Deterministic)"
        case .formatJSON: return "JSON Pretty"
        case .minifyJSON: return "JSON Minify"
        case .jsonToTypeScript: return "JSON → TypeScript"
        case .scrubLogs: return "Log / Stack Trace Scrub"
        case .inspectBash: return "Bash Inspect (Never Executes)"
        case .explainBash: return "Bash Explain (Local LLM)"
        case .correction: return "Correction Only (Local LLM)"
        case .professionalEmail: return "Professional Email (Local LLM)"
        case .rewrite: return "Rewrite (Local LLM)"
        case .slackSummary: return "Slack / Chat Summary (Local LLM)"
        case .tableToCSV: return "Table to CSV (Local LLM)"
        }
    }

    var frenchTitle: String {
        switch self {
        case .clean: return "Nettoyer & Masquer les Secrets"
        case .repairPDF: return "Réparer les Retours PDF"
        case .sanitizeRichText: return "Nettoyer le Texte Enrichi"
        case .urlClean: return "Purger les Traqueurs d'URL"
        case .secretScrub: return "Masquer les Secrets (Regex)"
        case .shareReady: return "Share-Ready (Anonymiser)"
        case .restoreIdentifiers: return "Restaurer Identifiants Originaux"
        case .convertTable: return "Convertir Tableau (CSV / Markdown)"
        case .formatJSON: return "Formater JSON (Pretty)"
        case .minifyJSON: return "Minifier JSON"
        case .jsonToTypeScript: return "JSON vers TypeScript"
        case .scrubLogs: return "Nettoyer Logs / Stack Trace"
        case .inspectBash: return "Inspecter Commande Bash"
        case .explainBash: return "Expliquer Bash (IA Locale)"
        case .correction: return "Correction Orthographe & Grammaire"
        case .professionalEmail: return "Courriel Professionnel (IA)"
        case .rewrite: return "Réécriture Professionnelle (IA)"
        case .slackSummary: return "Résumé Réunion / Slack (IA)"
        case .tableToCSV: return "Tableau vers CSV"
        }
    }

    var isMechanical: Bool {
        switch self {
        case .clean, .repairPDF, .sanitizeRichText, .urlClean, .secretScrub,
            .shareReady, .restoreIdentifiers, .convertTable, .formatJSON, .minifyJSON,
            .jsonToTypeScript, .scrubLogs, .inspectBash:
            return true
        case .explainBash, .correction, .professionalEmail, .rewrite, .slackSummary,
            .tableToCSV:
            return false
        }
    }
}

struct DeveloperActionOptions: Equatable, Sendable {
    var jsonIndentation: JSONIndentation = .twoSpaces
    var typeScriptRootName = "Root"
    var typeScriptIncludesExport = true
    var table = TableConversionOptions()
}
