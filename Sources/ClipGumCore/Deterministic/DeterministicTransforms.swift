import Foundation

public struct CoreTransformResult: Equatable, Sendable {
    public let output: String
    public let changeCount: Int

    public init(output: String, changeCount: Int) {
        self.output = output
        self.changeCount = changeCount
    }
}

public enum DeterministicTransformError: LocalizedError, Equatable, Sendable {
    case inputTooLarge
    case invalidJSON
    case invalidRootName
    case nestingTooDeep
    case invalidTable

    public var errorDescription: String? {
        switch self {
        case .inputTooLarge: return "The input exceeds the deterministic tool safety boundary."
        case .invalidJSON: return "The input is not valid JSON."
        case .invalidRootName: return "The TypeScript root name is not a valid identifier."
        case .nestingTooDeep: return "The input exceeds the deterministic nesting boundary."
        case .invalidTable: return "The delimited table is malformed."
        }
    }
}

/// Pure, synchronous operations shared by the CLI, App Intents, and custom-rule
/// host. None of these functions reads a pasteboard, opens a socket, or starts
/// a process. The app retains its richer document-aware implementations; this
/// module is deliberately limited to plain UTF-8 text for headless callers.
public enum DeterministicTransforms {
    public static let redactionPlaceholder = "[REDACTED]"
    public static let maximumJSONInputBytes = 16 * 1_024 * 1_024

    private static let trackingNames: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid",
        "mc_cid", "mc_eid", "mkt_tok"
    ]

    private static let urlExpression = try! NSRegularExpression(
        pattern: #"(?i)\bhttps?://[^\s<>\"'“”‘’]+"#
    )
    private static let awsExpression = try! NSRegularExpression(
        pattern: #"\b(?:A3T[A-Z0-9]|AKIA|ASIA|ABIA|ACCA)[A-Z2-7]{16}\b"#
    )
    private static let assignmentExpression = try! NSRegularExpression(
        pattern: #"\b(?:[a-z0-9]+[_.-])*(?:api[_-]?key|access[_-]?token|refresh[_-]?token|auth[_-]?token|client[_-]?secret|secret(?:[_-]?(?:access[_-]?)?key)?|token|passw(?:or)?d|credentials?)\b[\"']?\s*[:=]\s*[\"']?([-A-Za-z0-9._~+/=%]{12,})(?=\s|$|[&,#;|)\]\}>]|[\"'\x60]|\\)"#,
        options: [.caseInsensitive]
    )
    private static let bearerExpression = try! NSRegularExpression(
        pattern: #"\bBearer[ \t]+([-A-Za-z0-9._~+/=%]{12,})(?=\s|$|[&,#;|)\]\}>]|[\"'\x60]|\\)"#,
        options: [.caseInsensitive]
    )
    private static let providerTokenExpression = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9])(?:sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,})(?![A-Za-z0-9])"#
    )
    private static let ipv4Expression = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_.])(?:\d{1,3}\.){3}\d{1,3}(?![A-Za-z0-9_.])"#
    )
    private static let internalHostExpression = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_-])(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+(?:internal|intranet|intra|corp|local|lan|home\.arpa)(?![A-Za-z0-9_.-])"#,
        options: [.caseInsensitive]
    )

    public static func sanitize(_ input: String) -> CoreTransformResult {
        let urls = stripTrackingParameters(in: input)
        let secrets = redactSecrets(in: urls.output)
        return CoreTransformResult(
            output: secrets.output,
            changeCount: urls.changeCount + secrets.changeCount
        )
    }

    public static func stripTrackingParameters(in input: String) -> CoreTransformResult {
        let matches = urlExpression.matches(
            in: input,
            range: NSRange(input.startIndex..., in: input)
        )
        guard !matches.isEmpty else { return CoreTransformResult(output: input, changeCount: 0) }
        let output = NSMutableString(string: input)
        var removed = 0
        for match in matches.reversed() {
            let candidate = output.substring(with: match.range)
            let (url, punctuation) = trailingPunctuation(from: candidate)
            let result = cleanURL(url)
            guard result.changeCount > 0 else { continue }
            output.replaceCharacters(in: match.range, with: result.output + punctuation)
            removed += result.changeCount
        }
        return CoreTransformResult(output: output as String, changeCount: removed)
    }

    public static func redactSecrets(in input: String) -> CoreTransformResult {
        var current = input
        var count = 0
        for (expression, group) in [
            (awsExpression, 0), (assignmentExpression, 1),
            (bearerExpression, 1), (providerTokenExpression, 0),
            (internalHostExpression, 0)
        ] {
            let result = replace(current, expression: expression, group: group)
            current = result.output
            count += result.changeCount
        }
        let addresses = replaceIPv4(in: current)
        current = addresses.output
        count += addresses.changeCount
        return CoreTransformResult(output: current, changeCount: count)
    }

    private static func replace(
        _ input: String,
        expression: NSRegularExpression,
        group: Int
    ) -> CoreTransformResult {
        let matches = expression.matches(in: input, range: NSRange(input.startIndex..., in: input))
        guard !matches.isEmpty else { return CoreTransformResult(output: input, changeCount: 0) }
        let output = NSMutableString(string: input)
        var count = 0
        for match in matches.reversed() {
            let range = match.range(at: group)
            guard range.location != NSNotFound, range.length > 0 else { continue }
            output.replaceCharacters(in: range, with: redactionPlaceholder)
            count += 1
        }
        return CoreTransformResult(output: output as String, changeCount: count)
    }

    private static func replaceIPv4(in input: String) -> CoreTransformResult {
        let matches = ipv4Expression.matches(in: input, range: NSRange(input.startIndex..., in: input))
        guard !matches.isEmpty else { return CoreTransformResult(output: input, changeCount: 0) }
        let output = NSMutableString(string: input)
        var count = 0
        for match in matches.reversed() {
            let candidate = output.substring(with: match.range)
            let parts = candidate.split(separator: ".", omittingEmptySubsequences: false)
            let octets = parts.compactMap { Int($0) }
            guard parts.count == 4, octets.count == 4,
                  octets.allSatisfy({ (0...255).contains($0) }) else { continue }
            output.replaceCharacters(in: match.range, with: redactionPlaceholder)
            count += 1
        }
        return CoreTransformResult(output: output as String, changeCount: count)
    }

    private static func cleanURL(_ input: String) -> CoreTransformResult {
        guard validPercentEscapes(input), let components = URLComponents(string: input),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              let question = input.firstIndex(of: "?") else {
            return CoreTransformResult(output: input, changeCount: 0)
        }
        if let fragment = input.firstIndex(of: "#"), question > fragment {
            return CoreTransformResult(output: input, changeCount: 0)
        }
        let base = String(input[..<question])
        let remainder = String(input[input.index(after: question)...])
        let query: String
        let fragment: String
        if let hash = remainder.firstIndex(of: "#") {
            query = String(remainder[..<hash])
            fragment = String(remainder[hash...])
        } else {
            query = remainder
            fragment = ""
        }
        guard !query.isEmpty else { return CoreTransformResult(output: input, changeCount: 0) }
        var removed = 0
        let fields = query.split(separator: "&", omittingEmptySubsequences: false)
        let kept = fields.filter { field in
            let encoded = field.firstIndex(of: "=").map { String(field[..<$0]) } ?? String(field)
            let decoded = encoded.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
            guard let decoded else { return true }
            let name = decoded.lowercased()
            if name.hasPrefix("utm_") || trackingNames.contains(name) {
                removed += 1
                return false
            }
            return true
        }
        guard removed > 0 else { return CoreTransformResult(output: input, changeCount: 0) }
        let cleanedQuery = kept.joined(separator: "&")
        return CoreTransformResult(
            output: cleanedQuery.isEmpty ? base + fragment : base + "?" + cleanedQuery + fragment,
            changeCount: removed
        )
    }

    private static func validPercentEscapes(_ input: String) -> Bool {
        let scalars = Array(input.unicodeScalars)
        let hex = Set("0123456789abcdefABCDEF".unicodeScalars)
        for index in scalars.indices where scalars[index] == "%" {
            guard index + 2 < scalars.count, hex.contains(scalars[index + 1]),
                  hex.contains(scalars[index + 2]) else { return false }
        }
        return true
    }

    private static func trailingPunctuation(from candidate: String) -> (String, String) {
        var url = candidate
        var punctuation = ""
        let sentence: Set<Character> = [".", ",", ";", ":", "!", "?"]
        while let last = url.last, sentence.contains(last) {
            punctuation.insert(last, at: punctuation.startIndex)
            url.removeLast()
        }
        for (open, close) in [("(", ")"), ("[", "]"), ("{", "}")] as [(Character, Character)] {
            while url.last == close, url.filter({ $0 == close }).count > url.filter({ $0 == open }).count {
                punctuation.insert(close, at: punctuation.startIndex)
                url.removeLast()
            }
        }
        return (url, punctuation)
    }

    public static func jsonToTypeScript(
        _ input: String,
        rootName: String = "Root",
        includesExport: Bool = true
    ) throws -> String {
        guard input.utf8.count <= maximumJSONInputBytes else {
            throw DeterministicTransformError.inputTooLarge
        }
        guard validIdentifier(rootName) else { throw DeterministicTransformError.invalidRootName }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(
                with: Data(input.utf8),
                options: [.fragmentsAllowed]
            )
        } catch {
            throw DeterministicTransformError.invalidJSON
        }
        let type = try typeScriptType(for: object, depth: 0)
        return "\(includesExport ? "export " : "")type \(rootName) = \(type);"
    }

    private static func typeScriptType(for value: Any, depth: Int) throws -> String {
        guard depth <= 64 else { throw DeterministicTransformError.nestingTooDeep }
        switch value {
        case is NSNull: return "null"
        case is Bool: return "boolean"
        case is String: return "string"
        case is NSNumber: return "number"
        case let values as [Any]:
            guard !values.isEmpty else { return "unknown[]" }
            let types = try values.map { try typeScriptType(for: $0, depth: depth + 1) }
            let unique = Array(Set(types)).sorted()
            let element = unique.count == 1 ? unique[0] : unique.joined(separator: " | ")
            return unique.count > 1 ? "(\(element))[]" : "\(element)[]"
        case let object as [String: Any]:
            if object.isEmpty { return "{}" }
            let fields = try object.keys.sorted().map { key -> String in
                let fieldType = try typeScriptType(for: object[key]!, depth: depth + 1)
                return "  \(propertyName(key)): \(fieldType);"
            }
            return "{\n\(fields.joined(separator: "\n"))\n}"
        default:
            throw DeterministicTransformError.invalidJSON
        }
    }

    private static func validIdentifier(_ name: String) -> Bool {
        guard let first = name.first, first == "_" || first == "$" || first.isLetter,
              name.allSatisfy({ $0 == "_" || $0 == "$" || $0.isLetter || $0.isNumber }) else {
            return false
        }
        return !["type", "interface", "export", "string", "number", "boolean", "null", "unknown"].contains(name)
    }

    private static func propertyName(_ name: String) -> String {
        if validIdentifier(name) { return name }
        let escaped = name.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    /// Parses one RFC-4180-style CSV/TSV document and emits normalized CSV.
    /// It is intentionally deterministic and does not infer or invent values.
    public static func extractTable(_ input: String) throws -> String {
        guard input.utf8.count <= maximumJSONInputBytes else {
            throw DeterministicTransformError.inputTooLarge
        }
        let firstLine = input.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let delimiter: Character = firstLine.contains("\t") ? "\t" : (firstLine.contains(";") && !firstLine.contains(",") ? ";" : ",")
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = input.startIndex
        while index < input.endIndex {
            let character = input[index]
            if character == "\"" {
                let next = input.index(after: index)
                if quoted, next < input.endIndex, input[next] == "\"" {
                    field.append("\"")
                    index = input.index(after: next)
                    continue
                }
                quoted.toggle()
            } else if character == delimiter, !quoted {
                row.append(field)
                field = ""
            } else if character.isNewline, !quoted {
                row.append(field)
                field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
                if character == "\r", input.index(after: index) < input.endIndex,
                   input[input.index(after: index)] == "\n" {
                    index = input.index(after: index)
                }
            } else {
                field.append(character)
            }
            index = input.index(after: index)
        }
        if quoted { throw DeterministicTransformError.invalidTable }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        guard !rows.isEmpty else { throw DeterministicTransformError.invalidTable }
        return rows.map { row in
            row.map(csvField).joined(separator: ",")
        }.joined(separator: "\n")
    }

    private static func csvField(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
