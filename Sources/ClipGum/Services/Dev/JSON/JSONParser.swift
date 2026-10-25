import Foundation

/// Recursive-descent JSON parser with bounded depth and scalar-accurate source
/// locations. It accepts the complete JSON grammar and nothing else.
struct JSONParser {
    static let maximumDepth = 256
    static let maximumInputUTF8Bytes = 2 * 1_024 * 1_024

    private let scalars: [UnicodeScalar]
    private var index = 0
    private var line = 1
    private var column = 1
    private var previousWasCarriageReturn = false

    private init(_ input: String) {
        scalars = Array(input.unicodeScalars)
    }

    static func parse(_ input: String) throws -> JSONValue {
        guard input.utf8.count <= maximumInputUTF8Bytes else {
            throw JSONSyntaxError(
                message: "Input exceeds the 2 MiB JSON safety boundary.",
                line: 1,
                column: 1
            )
        }
        var parser = JSONParser(input)
        parser.consumeWhitespace()
        guard !parser.isAtEnd else {
            throw parser.error("Expected a JSON value.")
        }
        let value = try parser.parseValue(depth: 0)
        parser.consumeWhitespace()
        guard parser.isAtEnd else {
            throw parser.error("Unexpected content after the JSON value.")
        }
        return value
    }

    static func validate(_ input: String) -> JSONValidationResult {
        do {
            return JSONValidationResult(value: try parse(input), error: nil)
        } catch let error as JSONSyntaxError {
            return JSONValidationResult(value: nil, error: error)
        } catch {
            return JSONValidationResult(
                value: nil,
                error: JSONSyntaxError(message: "Unable to parse JSON.", line: 1, column: 1)
            )
        }
    }

    private var isAtEnd: Bool { index >= scalars.count }

    private func error(_ message: String) -> JSONSyntaxError {
        JSONSyntaxError(message: message, line: line, column: column)
    }

    @discardableResult
    private mutating func advance() -> UnicodeScalar? {
        guard !isAtEnd else { return nil }
        let scalar = scalars[index]
        index += 1
        if scalar == "\r" {
            line += 1
            column = 1
        } else if scalar == "\n" {
            if !previousWasCarriageReturn {
                line += 1
            }
            column = 1
        } else {
            column += 1
        }
        previousWasCarriageReturn = scalar == "\r"
        return scalar
    }

    private mutating func consumeWhitespace() {
        while let scalar = current, scalar == " " || scalar == "\t"
            || scalar == "\n" || scalar == "\r"
        {
            advance()
        }
    }

    private var current: UnicodeScalar? {
        guard !isAtEnd else { return nil }
        return scalars[index]
    }

    private mutating func parseValue(depth: Int) throws -> JSONValue {
        guard depth <= Self.maximumDepth else {
            throw error("Nesting exceeds the 256-level safety boundary.")
        }
        guard let scalar = current else {
            throw error("Expected a JSON value.")
        }
        switch scalar {
        case "{": return try parseObject(depth: depth + 1)
        case "[": return try parseArray(depth: depth + 1)
        case "\"": return .string(try parseString())
        case "t":
            try consumeLiteral("true")
            return .bool(true)
        case "f":
            try consumeLiteral("false")
            return .bool(false)
        case "n":
            try consumeLiteral("null")
            return .null
        case "-", "0"..."9":
            return .number(try parseNumber())
        default:
            throw error("Unexpected character while expecting a JSON value.")
        }
    }

    private mutating func parseObject(depth: Int) throws -> JSONValue {
        advance() // {
        consumeWhitespace()
        var members: [JSONMember] = []
        if current == "}" {
            advance()
            return .object(members)
        }
        while true {
            guard current == "\"" else {
                throw error("Expected a quoted object key.")
            }
            let key = try parseString()
            consumeWhitespace()
            guard current == ":" else {
                throw error("Expected ':' after the object key.")
            }
            advance()
            consumeWhitespace()
            let value = try parseValue(depth: depth)
            members.append(JSONMember(key: key, value: value))
            consumeWhitespace()
            if current == "}" {
                advance()
                return .object(members)
            }
            guard current == "," else {
                throw error("Expected ',' or '}' after the object member.")
            }
            advance()
            consumeWhitespace()
            if current == "}" {
                throw error("Trailing commas are not valid JSON.")
            }
        }
    }

    private mutating func parseArray(depth: Int) throws -> JSONValue {
        advance() // [
        consumeWhitespace()
        var values: [JSONValue] = []
        if current == "]" {
            advance()
            return .array(values)
        }
        while true {
            values.append(try parseValue(depth: depth))
            consumeWhitespace()
            if current == "]" {
                advance()
                return .array(values)
            }
            guard current == "," else {
                throw error("Expected ',' or ']' after the array element.")
            }
            advance()
            consumeWhitespace()
            if current == "]" {
                throw error("Trailing commas are not valid JSON.")
            }
        }
    }

    private mutating func parseString() throws -> String {
        guard current == "\"" else {
            throw error("Expected a string.")
        }
        advance()
        var output = ""
        while let scalar = current {
            if scalar == "\"" {
                advance()
                return output
            }
            if scalar.value < 0x20 {
                throw error("Unescaped control character in a string.")
            }
            if scalar != "\\" {
                output += String(scalar)
                advance()
                continue
            }
            advance()
            guard let escaped = current else {
                throw error("Unterminated escape sequence.")
            }
            switch escaped {
            case "\"":
                output += "\""
                advance()
            case "\\":
                output += "\\"
                advance()
            case "/":
                output += "/"
                advance()
            case "b":
                output += "\u{08}"
                advance()
            case "f":
                output += "\u{0C}"
                advance()
            case "n":
                output += "\n"
                advance()
            case "r":
                output += "\r"
                advance()
            case "t":
                output += "\t"
                advance()
            case "u":
                advance()
                output += try parseUnicodeEscape()
            default:
                throw error("Invalid string escape '\\\(escaped)'.")
            }
        }
        throw error("Unterminated string.")
    }

    private mutating func parseUnicodeEscape() throws -> String {
        let first = try parseFourHexDigits()
        if (0xD800...0xDBFF).contains(first) {
            guard current == "\\" else {
                throw error("A high surrogate must be followed by a low surrogate.")
            }
            advance()
            guard current == "u" else {
                throw error("A high surrogate must be followed by a low surrogate.")
            }
            advance()
            let second = try parseFourHexDigits()
            guard (0xDC00...0xDFFF).contains(second) else {
                throw error("Invalid low surrogate in a Unicode escape pair.")
            }
            let combined = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
            guard let scalar = UnicodeScalar(combined) else {
                throw error("Invalid Unicode scalar value.")
            }
            return String(scalar)
        }
        guard !(0xDC00...0xDFFF).contains(first), let scalar = UnicodeScalar(first) else {
            throw error("Unpaired surrogate in a Unicode escape.")
        }
        return String(scalar)
    }

    private mutating func parseFourHexDigits() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let scalar = current, let digit = scalar.hexDigitValue else {
                throw error("Expected four hexadecimal digits in a Unicode escape.")
            }
            value = value * 16 + UInt32(digit)
            advance()
        }
        return value
    }

    private mutating func consumeLiteral(_ literal: String) throws {
        for expected in literal.unicodeScalars {
            guard current == expected else {
                throw error("Invalid literal; expected '\(literal)'.")
            }
            advance()
        }
    }

    private mutating func parseNumber() throws -> String {
        let start = index
        if current == "-" {
            advance()
        }
        guard let first = current, ("0"..."9").contains(first) else {
            throw error("Expected a digit in the number.")
        }
        if first == "0" {
            advance()
            if let next = current, ("0"..."9").contains(next) {
                throw error("Leading zeros are not valid JSON numbers.")
            }
        } else {
            consumeDigits()
        }
        if current == "." {
            advance()
            guard let next = current, ("0"..."9").contains(next) else {
                throw error("Expected a digit after the decimal point.")
            }
            consumeDigits()
        }
        if current == "e" || current == "E" {
            advance()
            if current == "+" || current == "-" {
                advance()
            }
            guard let next = current, ("0"..."9").contains(next) else {
                throw error("Expected digits in the number exponent.")
            }
            consumeDigits()
        }
        return scalars[start..<index].map(String.init).joined()
    }

    private mutating func consumeDigits() {
        while let scalar = current, ("0"..."9").contains(scalar) {
            advance()
        }
    }
}

private extension UnicodeScalar {
    var hexDigitValue: Int? {
        switch self {
        case "0"..."9": return Int(value - 0x30)
        case "a"..."f": return Int(value - 0x61) + 10
        case "A"..."F": return Int(value - 0x41) + 10
        default: return nil
        }
    }
}
