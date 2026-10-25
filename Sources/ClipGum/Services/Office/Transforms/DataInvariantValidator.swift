import Foundation

/// Exact multiset checks for data that Office language actions must never
/// rewrite. Formatting/ordering may change only outside these protected tokens.
struct DataInvariantValidator {
    private static let numericAndDatePattern = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}_])(?:\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}[-/]\d{1,2}[-/]\d{2,4}|\d{1,2}:\d{2}(?::\d{2})?|[-+]?(?:\d{1,3}(?:[ \u00A0]\d{3})+|\d{1,3}(?:,\d{3})+|\d{1,3}(?:\.\d{3})+|\d+)(?:[.,]\d+)?(?:[eE][+-]?\d+)?%?)(?![\p{L}\p{N}_])"#
    )

    private static let namedDatePattern = makeNamedDatePattern()

    func issues(source: String, output: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let sourceNumbers = (matches(Self.numericAndDatePattern, in: source)
            + matches(Self.namedDatePattern, in: source)).sorted()
        let outputNumbers = (matches(Self.numericAndDatePattern, in: output)
            + matches(Self.namedDatePattern, in: output)).sorted()
        if sourceNumbers != outputNumbers
        {
            issues.append(ValidationIssue(
                code: .numbersChanged,
                severity: .error,
                message: "Numbers, percentages, or dates were added, removed, or changed."
            ))
        }
        let sourceCurrency = currencySymbols(in: source)
        let outputCurrency = currencySymbols(in: output)
        if sourceCurrency != outputCurrency {
            issues.append(ValidationIssue(
                code: .currencyChanged,
                severity: .error,
                message: "Currency symbols ($ / €) were added, removed, or changed."
            ))
        }
        let sourceFormulas = SpreadsheetFormulaExtractor.formulas(in: source).sorted()
        let outputFormulas = SpreadsheetFormulaExtractor.formulas(in: output).sorted()
        if sourceFormulas != outputFormulas {
            issues.append(ValidationIssue(
                code: .formulaChanged,
                severity: .error,
                message: "A spreadsheet formula was added, removed, or changed."
            ))
        }
        return issues
    }

    private static func makeNamedDatePattern() -> NSRegularExpression {
        let month = #"Jan(?:uary)?|Janvier|Feb(?:ruary)?|Février|Mar(?:ch)?|Mars|Apr(?:il)?|Avril|May|Mai|June?|Juin|July?|Juillet|Aug(?:ust)?|Août|Sept?(?:ember)?|Septembre|Oct(?:ober)?|Octobre|Nov(?:ember)?|Novembre|Dec(?:ember)?|Décembre"#
        let pattern = #"(?i)(?<![\p{L}\p{N}_])(?:(?:"# + month
            + #")\s+\d{1,2}(?:st|nd|rd|th)?(?:,?\s+\d{4})?|\d{1,2}(?:st|nd|rd|th)?\s+(?:de\s+)?(?:"#
            + month + #")(?:\s+\d{4})?|(?:"# + month
            + #")\s+\d{4})(?![\p{L}\p{N}_])"#
        return try! NSRegularExpression(pattern: pattern)
    }

    private func currencySymbols(in text: String) -> [String] {
        text.compactMap { character in
            character == "$" || character == "€" ? String(character) : nil
        }.sorted()
    }

    private func matches(_ regex: NSRegularExpression, in text: String) -> [String] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }
}

private enum SpreadsheetFormulaExtractor {
    static func formulas(in text: String) -> [String] {
        let characters = Array(text)
        var formulas: [String] = []
        var index = 0
        while index < characters.count {
            guard characters[index] == "=", isBoundary(before: index, in: characters) else {
                index += 1
                continue
            }
            let start = index
            index += 1
            var depth = 0
            var quote = false
            var hasContent = false
            while index < characters.count {
                let character = characters[index]
                if quote {
                    hasContent = true
                    if character == "\"" {
                        if index + 1 < characters.count, characters[index + 1] == "\"" {
                            index += 2
                            continue
                        }
                        quote = false
                    }
                    index += 1
                    continue
                }
                if character == "\"" {
                    quote = true
                    hasContent = true
                } else if character == "(" {
                    depth += 1
                    hasContent = true
                } else if character == ")" {
                    guard depth > 0 else { break }
                    depth -= 1
                    hasContent = true
                } else if depth == 0, character.isWhitespace || character == ";" {
                    break
                } else if character == "\n" || character == "\r" || character == "\t" {
                    break
                } else {
                    hasContent = hasContent || character.isLetter || character.isNumber
                }
                index += 1
            }
            if hasContent {
                var formula = String(characters[start..<index])
                while let last = formula.last, [",", ".", ";", "?", "!"].contains(last) {
                    formula.removeLast()
                }
                if formula.count > 1 { formulas.append(formula) }
            } else {
                index = start + 1
            }
        }
        return formulas
    }

    private static func isBoundary(before index: Int, in characters: [Character]) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1]
        return previous.isWhitespace || ["\"", "'", "(", "[", "{", "|"].contains(previous)
    }
}
