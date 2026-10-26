import Foundation

/// Analyzes clipboard contents to understand the user's intent, the probability of need,
/// and recommends the most relevant privacy or formatting transformation.
public struct IntentPrediction: Equatable, Sendable {
    public enum IntentCategory: String, CaseIterable, Sendable {
        case sanitizeURL = "Nettoyage d'URL & Traceurs"
        case developerToken = "Préservation de Clé / Token Développeur"
        case formatJSON = "Formatage JSON & Typage"
        case convertTable = "Conversion Tabulaire / Markdown"
        case repairPDF = "Réparation de texte & Césures PDF"
        case anonymizePII = "Anonymisation PII & Logs"
        case summarizeNotes = "Synthèse & Points Clés"
        case grammarAndTone = "Correction & Style Professionnel"
        case generalClean = "Nettoyage Rapide & Espaces"
    }

    public let category: IntentCategory
    public let probability: Double // 0.0 to 1.0 (e.g. 0.98 = 98%)
    public let confidenceText: String
    public let diagnosis: String
    public let suggestedActionName: String
    public let isHighConfidence: Bool

    public var percentageString: String {
        "\(Int(probability * 100))%"
    }
}

public struct IntentProbabilityEngine: Sendable {
    public static let shared = IntentProbabilityEngine()

    public init() {}

    /// Analyzes arbitrary clipboard text to predict the user's intent and probability of need.
    public func predict(for text: String) -> IntentPrediction {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return IntentPrediction(
                category: .generalClean,
                probability: 0.10,
                confidenceText: "Faible (10%)",
                diagnosis: "Presse-papiers vide ou espaces uniquement",
                suggestedActionName: "Aucune action requise",
                isHighConfidence: false
            )
        }

        // 1. Check for Tracking URLs
        let urlTrackerScore = calculateURLTrackerScore(trimmed)
        if urlTrackerScore > 0.60 {
            return IntentPrediction(
                category: .sanitizeURL,
                probability: min(0.99, urlTrackerScore),
                confidenceText: "Très Élevée (\(Int(min(0.99, urlTrackerScore) * 100))%)",
                diagnosis: "URL avec paramètres de pistage publicitaire détectés (UTM, Facebook, Google)",
                suggestedActionName: "⚡ Purger les traceurs d'URL",
                isHighConfidence: true
            )
        }

        // 2. Check for Developer Tokens / Secrets
        let tokenScore = calculateDeveloperTokenScore(trimmed)
        if tokenScore > 0.65 {
            return IntentPrediction(
                category: .developerToken,
                probability: min(0.98, tokenScore),
                confidenceText: "Très Élevée (\(Int(min(0.98, tokenScore) * 100))%)",
                diagnosis: "Jeton d'authentification API détecté (GitHub PAT, OpenAI, AWS, ou Clé Secrète)",
                suggestedActionName: "🔑 Préserver le token en clair (Mode Dév)",
                isHighConfidence: true
            )
        }

        // 3. Check for JSON Content
        let jsonScore = calculateJSONScore(trimmed)
        if jsonScore > 0.70 {
            return IntentPrediction(
                category: .formatJSON,
                probability: min(0.97, jsonScore),
                confidenceText: "Élevée (\(Int(min(0.97, jsonScore) * 100))%)",
                diagnosis: "Structure JSON détectée nécessitant indentation et validation syntaxique",
                suggestedActionName: "📐 Formater & Indenter JSON",
                isHighConfidence: true
            )
        }

        // 4. Check for Tabular / CSV Data
        let tableScore = calculateTableScore(trimmed)
        if tableScore > 0.65 {
            return IntentPrediction(
                category: .convertTable,
                probability: min(0.96, tableScore),
                confidenceText: "Élevée (\(Int(min(0.96, tableScore) * 100))%)",
                diagnosis: "Lignes de données tabulaires (CSV ou séparateurs tabulation) identifiées",
                suggestedActionName: "📊 Convertir en Tableau Markdown",
                isHighConfidence: true
            )
        }

        // 5. Check for PDF Artifacts (broken line wraps, hyphenated words)
        let pdfScore = calculatePDFScore(trimmed)
        if pdfScore > 0.60 {
            return IntentPrediction(
                category: .repairPDF,
                probability: min(0.93, pdfScore),
                confidenceText: "Moyenne/Élevée (\(Int(min(0.93, pdfScore) * 100))%)",
                diagnosis: "Texte extrait de PDF présentant des césures de mots ou retours forcés",
                suggestedActionName: "📄 Réparer les artefacts PDF",
                isHighConfidence: true
            )
        }

        // 6. Check for Server Logs / PII (IPs, emails)
        let piiScore = calculatePIIScore(trimmed)
        if piiScore > 0.60 {
            return IntentPrediction(
                category: .anonymizePII,
                probability: min(0.94, piiScore),
                confidenceText: "Élevée (\(Int(min(0.94, piiScore) * 100))%)",
                diagnosis: "Adresses IP, logs de serveur ou identifiants personnels détectés",
                suggestedActionName: "🛡️ Anonymiser les logs & PII",
                isHighConfidence: true
            )
        }

        // 7. Check for Long Unstructured Text / Notes
        if trimmed.count > 300 && trimmed.contains("\n") {
            return IntentPrediction(
                category: .summarizeNotes,
                probability: 0.85,
                confidenceText: "Probable (85%)",
                diagnosis: "Document ou notes longues propices à une synthèse condensée",
                suggestedActionName: "✨ Résumer en points clés",
                isHighConfidence: true
            )
        }

        // 8. Default: General clean
        return IntentPrediction(
            category: .generalClean,
            probability: 0.72,
            confidenceText: "Standard (72%)",
            diagnosis: "Texte général - nettoyage typographique et suppression des espaces superflus",
            suggestedActionName: "🧹 Nettoyer le formatage",
            isHighConfidence: false
        )
    }

    // MARK: - Probability Scoring Functions

    private func calculateURLTrackerScore(_ text: String) -> Double {
        guard text.hasPrefix("http://") || text.hasPrefix("https://") else { return 0.0 }
        var score: Double = 0.40
        let trackers = ["utm_source", "utm_medium", "utm_campaign", "fbclid", "gclid", "msclkid", "ref_src", "mc_eid"]
        for tracker in trackers {
            if text.contains(tracker) {
                score += 0.20
            }
        }
        return min(1.0, score)
    }

    private func calculateDeveloperTokenScore(_ text: String) -> Double {
        if text.hasPrefix("ghp_") || text.hasPrefix("github_pat_") || text.hasPrefix("gho_") {
            return 0.99
        }
        if text.hasPrefix("sk-") || text.contains("sk-proj-") {
            return 0.98
        }
        if text.contains("AKIA") || text.contains("ASIA") {
            return 0.96
        }
        if text.range(of: #"(?i)(api[_-]?key|access[_-]?token|secret)\s*[:=]\s*["']?[\w-]{16,}"#, options: .regularExpression) != nil {
            return 0.92
        }
        return 0.0
    }

    private func calculateJSONScore(_ text: String) -> Double {
        let isBracketed = (text.hasPrefix("{") && text.hasSuffix("}")) || (text.hasPrefix("[") && text.hasSuffix("]"))
        guard isBracketed else { return 0.0 }
        if let data = text.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return 0.97
        }
        return 0.40
    }

    private func calculateTableScore(_ text: String) -> Double {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { return 0.0 }
        let commaCounts = lines.map { $0.filter { $0 == "," }.count }
        let tabCounts = lines.map { $0.filter { $0 == "\t" }.count }
        if let firstTab = tabCounts.first, firstTab >= 1, tabCounts.allSatisfy({ $0 == firstTab }) {
            return 0.96
        }
        if let firstComma = commaCounts.first, firstComma >= 1, commaCounts.allSatisfy({ $0 == firstComma }) {
            return 0.93
        }
        return 0.0
    }

    private func calculatePDFScore(_ text: String) -> Double {
        var score = 0.0
        if text.contains("-\n") || text.contains("­\n") {
            score += 0.50
        }
        let lines = text.components(separatedBy: .newlines)
        if lines.count > 3 {
            let shortLines = lines.filter { $0.count > 10 && $0.count < 60 && !$0.hasSuffix(".") }
            if Double(shortLines.count) / Double(lines.count) > 0.4 {
                score += 0.45
            }
        }
        return min(1.0, score)
    }

    private func calculatePIIScore(_ text: String) -> Double {
        var matches = 0
        // IPv4 regex
        if text.range(of: #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, options: .regularExpression) != nil {
            matches += 1
        }
        // Email regex
        if text.range(of: #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b"#, options: .regularExpression) != nil {
            matches += 1
        }
        if matches >= 2 { return 0.95 }
        if matches == 1 { return 0.75 }
        return 0.0
    }
}
