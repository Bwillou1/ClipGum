import AppKit
import Foundation

enum OfficeAppKind: String, Equatable, Sendable {
    case word
    case excel
    case outlook
    case mail
    case slack
    case browser
    case other
}

struct OfficeAppProfile: Equatable, Sendable {
    let kind: OfficeAppKind
    let displayName: String

    var suggestedActions: [SmartPasteAction] {
        switch kind {
        case .word:
            return [.sanitizeRichText, .repairPDF, .correction]
        case .excel:
            return [.convertTable, .tableToCSV]
        case .browser:
            return [.sanitizeRichText, .convertTable, .urlClean]
        case .outlook, .mail:
            return [.professionalEmail, .correction]
        case .slack:
            return [.clean, .slackSummary]
        case .other:
            return []
        }
    }
}

/// Pure identifier mapping, separated from NSWorkspace for deterministic tests.
enum OfficeAppProfileResolver {
    static func profile(bundleIdentifier: String?, localizedName: String?) -> OfficeAppProfile {
        let bundle = bundleIdentifier?.lowercased() ?? ""
        let name = localizedName?.lowercased() ?? ""
        let kind: OfficeAppKind
        switch bundle {
        case "com.microsoft.word": kind = .word
        case "com.microsoft.excel": kind = .excel
        case "com.microsoft.outlook": kind = .outlook
        case "com.apple.mail": kind = .mail
        case "com.tinyspeck.slackmacgap", "com.tinyspeck.slackmacgap.helper": kind = .slack
        case "com.apple.safari", "com.google.chrome", "com.microsoft.edgemac",
            "org.mozilla.firefox", "company.thebrowser.browser":
            kind = .browser
        default:
            if name.contains("word") { kind = .word }
            else if name.contains("excel") { kind = .excel }
            else if name.contains("outlook") { kind = .outlook }
            else if name.contains("mail") { kind = .mail }
            else if name.contains("slack") { kind = .slack }
            else if ["safari", "chrome", "firefox", "edge", "arc"].contains(where: { name.contains($0) }) {
                kind = .browser
            } else { kind = .other }
        }
        return OfficeAppProfile(
            kind: kind,
            displayName: localizedName ?? bundleIdentifier ?? "Target app"
        )
    }

    @MainActor
    static func profile(application: NSRunningApplication?) -> OfficeAppProfile {
        profile(
            bundleIdentifier: application?.bundleIdentifier,
            localizedName: application?.localizedName
        )
    }
}
