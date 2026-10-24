import Foundation

struct ValidationIssue: Equatable, Sendable {
    enum Severity: Equatable, Sendable {
        case warning
        case error
    }

    enum Code: String, Equatable, Sendable {
        case emptyOutput
        case invalidControlCharacter
        case secretRegenerated
        case missingRedactionMarker
        case numbersChanged
        case codeChanged
        case semanticDivergence
        case invalidTableSchema
        case invalidCSV
        case tableDataChanged
    }

    let code: Code
    let severity: Severity
    let message: String
}

struct ValidationReport: Equatable, Sendable {
    let issues: [ValidationIssue]

    var errors: [ValidationIssue] {
        issues.filter { $0.severity == .error }
    }

    var warnings: [ValidationIssue] {
        issues.filter { $0.severity == .warning }
    }

    var canExport: Bool {
        errors.isEmpty
    }

    static let approved = ValidationReport(issues: [])
}

/// Conservative post-generation checks. Passing them is not a semantic proof;
/// failing any error-severity check makes model output non-exportable.
struct OutputValidator {
    private let secretRedactor = SecretRedactor(
        placeholder: RuleCleaningService.redactionPlaceholder
    )
    private let tableExtractor = TableDataExtractor()

    private static let numericPattern = try! NSRegularExpression(
        pattern: #"\d+(?:[.,:/-]\d+)*(?:[eE][+-]?\d+)?%?"#
    )
    private static let fencedCodePattern = try! NSRegularExpression(
        pattern: #"(?s)```.*?```"#
    )
    private static let inlineCodePattern = try! NSRegularExpression(
        pattern: #"(?<!`)`[^`\r\n]+`(?!`)"#
    )
    func validate(
        action: SmartPasteAction,
        source: String,
        output: String
    ) -> ValidationReport {
        var issues: [ValidationIssue] = []
        if output.isEmpty {
            issues.append(issue(
                .emptyOutput,
                .error,
                "The model returned no usable text. Its output cannot be pasted or copied."
            ))
            return ValidationReport(issues: issues)
        }

        if output.unicodeScalars.contains(where: {
            ($0.value < 32 && $0 != "\n" && $0 != "\t" && $0 != "\r") || $0.value == 127
        }) {
            issues.append(issue(
                .invalidControlCharacter,
                .error,
                "The response contains unsupported control characters."
            ))
        }

        if secretRedactor.redactSecrets(in: output).changeCount > 0 {
            issues.append(issue(
                .secretRegenerated,
                .error,
                "A detectable secret or sensitive internal value appeared in the model response."
            ))
        }

        let placeholder = RuleCleaningService.redactionPlaceholder
        let sourceMarkers = occurrenceCount(of: placeholder, in: source)
        let outputMarkers = occurrenceCount(of: placeholder, in: output)
        if action != .explainBash, outputMarkers < sourceMarkers {
            issues.append(issue(
                .missingRedactionMarker,
                .error,
                "One or more deterministic redaction markers were lost."
            ))
        }

        switch action {
        case .correction, .rewrite:
            if matches(Self.numericPattern, in: source).sorted()
                != matches(Self.numericPattern, in: output).sorted()
            {
                issues.append(issue(
                    .numbersChanged,
                    .error,
                    "Numeric tokens were added, removed, or changed."
                ))
            }
            if matches(Self.fencedCodePattern, in: source).sorted()
                != matches(Self.fencedCodePattern, in: output).sorted()
                || matches(Self.inlineCodePattern, in: source).sorted()
                    != matches(Self.inlineCodePattern, in: output).sorted()
            {
                issues.append(issue(
                    .codeChanged,
                    .error,
                    "A fenced code block or inline code span was added, removed, or changed."
                ))
            }
            if let semantic = SemanticDivergenceDetector.issue(source: source, output: output, action: action) {
                issues.append(semantic)
            }
        case .tableToCSV:
            validateCSV(source: source, output: output, issues: &issues)
        case .explainBash, .clean, .urlClean, .secretScrub, .shareReady,
            .restoreIdentifiers, .formatJSON, .minifyJSON, .jsonToTypeScript,
            .scrubLogs, .inspectBash:
            break
        }
        return ValidationReport(issues: issues)
    }

    private func validateCSV(source: String, output: String, issues: inout [ValidationIssue]) {
        let sourceRows: [[String]]
        do {
            sourceRows = try tableExtractor.rows(from: source)
        } catch {
            issues.append(issue(
                .invalidTableSchema,
                .error,
                "The source is not a supported, consistently aligned TSV or Markdown table."
            ))
            return
        }

        do {
            let csv = try CSVDocument.parse(output)
            guard let columns = csv.rows.first?.count, columns > 0,
                csv.rows.allSatisfy({ $0.count == columns })
            else {
                issues.append(issue(
                    .invalidCSV,
                    .error,
                    "The CSV response has inconsistent column alignment or no rows."
                ))
                return
            }
            if csv.rows != sourceRows {
                issues.append(issue(
                    .tableDataChanged,
                    .error,
                    "CSV cells, rows, columns, or ordering differ from the source table."
                ))
            }
        } catch {
            issues.append(issue(
                .invalidCSV,
                .error,
                "The model response is not well-formed CSV."
            ))
        }
    }

    private func occurrenceCount(of needle: String, in text: String) -> Int {
        guard !needle.isEmpty else {
            return 0
        }
        return text.components(separatedBy: needle).count - 1
    }

    private func matches(_ regex: NSRegularExpression, in text: String) -> [String] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else {
                return nil
            }
            return String(text[range])
        }
    }

    private func issue(
        _ code: ValidationIssue.Code,
        _ severity: ValidationIssue.Severity,
        _ message: String
    ) -> ValidationIssue {
        ValidationIssue(code: code, severity: severity, message: message)
    }
}

private enum SemanticDivergenceDetector {
    private static let wordPattern = try! NSRegularExpression(
        pattern: #"[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*"#
    )

    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "been", "but", "by", "for",
        "from", "had", "has", "have", "i", "in", "is", "it", "its", "of", "on",
        "or", "our", "that", "the", "their", "this", "to", "was", "we", "were",
        "will", "with", "you", "your"
    ]

    static func issue(
        source: String,
        output: String,
        action: SmartPasteAction
    ) -> ValidationIssue? {
        let sourceTerms = terms(source)
        let outputTerms = terms(output)
        guard !sourceTerms.isEmpty, !outputTerms.isEmpty else {
            return ValidationIssue(
                code: .semanticDivergence,
                severity: .error,
                message: "The response has no meaningful lexical overlap with the source."
            )
        }

        if sourceTerms.count < 4 || outputTerms.count < 4 {
            guard action == .correction else {
                return nil
            }
            let score = normalizedEditDistance(source: source, output: output)
            if score > 0.85 {
                return ValidationIssue(
                    code: .semanticDivergence,
                    severity: .error,
                    message: "The short response diverges too far from the source for automatic approval."
                )
            }
            if score > 0.6 {
                return ValidationIssue(
                    code: .semanticDivergence,
                    severity: .warning,
                    message: "Semantic similarity is uncertain; review this short correction carefully."
                )
            }
            return nil
        }

        let intersection = sourceTerms.intersection(outputTerms).count
        let containment = Double(intersection) / Double(min(sourceTerms.count, outputTerms.count))
        let divergence = 1 - containment
        let errorThreshold = action == .correction ? 0.75 : 0.90
        let warningThreshold = action == .correction ? 0.45 : 0.70
        if divergence >= errorThreshold {
            return ValidationIssue(
                code: .semanticDivergence,
                severity: .error,
                message: "Semantic divergence is too high for automatic approval."
            )
        }
        if divergence >= warningThreshold {
            return ValidationIssue(
                code: .semanticDivergence,
                severity: .warning,
                message: "The semantic-overlap heuristic flagged this response for careful review."
            )
        }
        return nil
    }

    private static func terms(_ text: String) -> Set<String> {
        let words = wordPattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { match -> String? in
                guard let range = Range(match.range, in: text) else {
                    return nil
                }
                return String(text[range]).lowercased()
            }
        return Set(words.filter { !stopWords.contains($0) })
    }

    private static func normalizedEditDistance(source: String, output: String) -> Double {
        let lhs = Array(source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        let rhs = Array(output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        let denominator = max(lhs.count, rhs.count)
        guard denominator > 0 else {
            return 0
        }
        // This fallback is only used for fewer than four lexical terms.
        // Bound pathological allocation even when called directly by a test.
        guard lhs.count <= 1_024, rhs.count <= 1_024 else {
            return 1
        }
        var previous = Array(0...rhs.count)
        for (i, left) in lhs.enumerated() {
            var current = [i + 1]
            current.reserveCapacity(rhs.count + 1)
            for (j, right) in rhs.enumerated() {
                let substitution = previous[j] + (left == right ? 0 : 1)
                current.append(min(substitution, min(previous[j + 1] + 1, current[j] + 1)))
            }
            previous = current
        }
        return Double(previous[rhs.count]) / Double(denominator)
    }
}
