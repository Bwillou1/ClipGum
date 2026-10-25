import Combine
import Foundation

public struct LiveInspectorLogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let date: Date
    public let trigger: String
    public let contentType: String
    public let originalSnippet: String
    public let cleanedSnippet: String
    public let trackersRemoved: Int
    public let secretsRedacted: Int
    public let latencyMs: Double
    public let actionName: String

    public var timestampFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

@MainActor
public final class LiveInspectorEngine: ObservableObject {
    public static let shared = LiveInspectorEngine()

    @Published public private(set) var entries: [LiveInspectorLogEntry] = []
    @Published public var filterQuery: String = ""
    @Published public var selectedCategory: String = "Tous"

    public var totalTrackersRemoved: Int {
        entries.reduce(0) { $0 + $1.trackersRemoved }
    }

    public var totalSecretsRedacted: Int {
        entries.reduce(0) { $0 + $1.secretsRedacted }
    }

    public var averageLatencyMs: Double {
        guard !entries.isEmpty else { return 0 }
        let total = entries.reduce(0.0) { $0 + $1.latencyMs }
        return total / Double(entries.count)
    }

    public var filteredEntries: [LiveInspectorLogEntry] {
        entries.filter { entry in
            let matchesCategory: Bool
            switch selectedCategory {
            case "Secrets":
                matchesCategory = entry.secretsRedacted > 0 || entry.contentType.contains("Secret")
            case "URLs":
                matchesCategory = entry.trackersRemoved > 0 || entry.contentType.contains("URL")
            case "Tableaux":
                matchesCategory = entry.contentType.contains("Table")
            case "IA":
                matchesCategory = entry.actionName.contains("IA") || entry.actionName.contains("LLM")
            default:
                matchesCategory = true
            }

            if !filterQuery.isEmpty {
                let q = filterQuery.lowercased()
                return matchesCategory && (
                    entry.originalSnippet.lowercased().contains(q) ||
                    entry.cleanedSnippet.lowercased().contains(q) ||
                    entry.actionName.lowercased().contains(q) ||
                    entry.contentType.lowercased().contains(q)
                )
            }
            return matchesCategory
        }
    }

    public func record(
        trigger: String,
        contentType: String,
        original: String,
        cleaned: String,
        trackersRemoved: Int = 0,
        secretsRedacted: Int = 0,
        latencyMs: Double,
        actionName: String
    ) {
        let entry = LiveInspectorLogEntry(
            date: Date(),
            trigger: trigger,
            contentType: contentType,
            originalSnippet: String(original.prefix(120)),
            cleanedSnippet: String(cleaned.prefix(120)),
            trackersRemoved: trackersRemoved,
            secretsRedacted: secretsRedacted,
            latencyMs: latencyMs,
            actionName: actionName
        )
        entries.insert(entry, at: 0)
        if entries.count > 100 {
            entries.removeLast(entries.count - 100)
        }
    }

    public func clear() {
        entries.removeAll()
    }
}
