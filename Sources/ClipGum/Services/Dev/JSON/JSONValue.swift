import Foundation

struct JSONMember: Equatable, Sendable {
    let key: String
    let value: JSONValue
}

/// Native JSON AST used by formatting, validation, and TypeScript inference.
/// Numbers retain their validated source lexeme so large values never pass
/// through a floating-point conversion.
indirect enum JSONValue: Equatable, Sendable {
    case object([JSONMember])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null
}

enum JSONIndentation: String, CaseIterable, Identifiable, Sendable {
    case twoSpaces
    case fourSpaces
    case tabs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twoSpaces: return "2 spaces"
        case .fourSpaces: return "4 spaces"
        case .tabs: return "Tabs"
        }
    }

    var unit: String {
        switch self {
        case .twoSpaces: return "  "
        case .fourSpaces: return "    "
        case .tabs: return "\t"
        }
    }
}

struct JSONSyntaxError: LocalizedError, Equatable, Sendable {
    let message: String
    let line: Int
    let column: Int

    var errorDescription: String? {
        "JSON error at line \(line), column \(column): \(message)"
    }
}

struct JSONValidationResult: Equatable, Sendable {
    let value: JSONValue?
    let error: JSONSyntaxError?

    var isValid: Bool { value != nil && error == nil }
}

enum JSONRenderer {
    static func render(_ value: JSONValue, indentation: JSONIndentation?) -> String {
        guard let indentation else {
            return compact(value)
        }
        return pretty(value, indentation: indentation, level: 0)
    }

    static func escapedString(_ value: String) -> String {
        var output = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\u{08}": output += "\\b"
            case "\u{0C}": output += "\\f"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case "\u{2028}": output += "\\u2028"
            case "\u{2029}": output += "\\u2029"
            default:
                if scalar.value < 0x20 {
                    output += String(format: "\\u%04X", scalar.value)
                } else {
                    output += String(scalar)
                }
            }
        }
        output += "\""
        return output
    }

    private static func compact(_ value: JSONValue) -> String {
        switch value {
        case .object(let members):
            return "{" + members.map {
                escapedString($0.key) + ":" + compact($0.value)
            }.joined(separator: ",") + "}"
        case .array(let values):
            return "[" + values.map(compact).joined(separator: ",") + "]"
        case .string(let string):
            return escapedString(string)
        case .number(let number):
            return number
        case .bool(let bool):
            return bool ? "true" : "false"
        case .null:
            return "null"
        }
    }

    private static func pretty(
        _ value: JSONValue,
        indentation: JSONIndentation,
        level: Int
    ) -> String {
        switch value {
        case .object(let members):
            guard !members.isEmpty else { return "{}" }
            let nested = members.map { member in
                String(repeating: indentation.unit, count: level + 1)
                    + escapedString(member.key) + ": "
                    + pretty(member.value, indentation: indentation, level: level + 1)
            }.joined(separator: ",\n")
            return "{\n" + nested + "\n"
                + String(repeating: indentation.unit, count: level) + "}"
        case .array(let values):
            guard !values.isEmpty else { return "[]" }
            let nested = values.map {
                String(repeating: indentation.unit, count: level + 1)
                    + pretty($0, indentation: indentation, level: level + 1)
            }.joined(separator: ",\n")
            return "[\n" + nested + "\n"
                + String(repeating: indentation.unit, count: level) + "]"
        case .string, .number, .bool, .null:
            return compact(value)
        }
    }
}
