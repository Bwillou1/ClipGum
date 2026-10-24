import Foundation

struct HTMLAttribute: Equatable, Sendable {
    let name: String
    let value: String
}

enum HTMLToken: Equatable, Sendable {
    case startTag(name: String, attributes: [HTMLAttribute], selfClosing: Bool)
    case endTag(name: String)
    case text(String)
    case ignored
}

enum HTMLScanError: LocalizedError, Equatable, Sendable {
    case inputTooLarge

    var errorDescription: String? {
        "HTML input exceeds the 4 MiB Office safety boundary."
    }
}

/// Bounded, regex-free scanner for clipboard HTML. It intentionally emits a
/// token stream rather than executing or rendering a browser document.
struct HTMLScanner {
    static let maximumInputUTF8Bytes = 4 * 1_024 * 1_024

    func scan(_ input: String) throws -> [HTMLToken] {
        guard input.utf8.count <= Self.maximumInputUTF8Bytes else {
            throw HTMLScanError.inputTooLarge
        }
        var scanner = Scanner(input)
        return scanner.scanTokens()
    }
}

private struct Scanner {
    private let characters: [Character]
    private var index = 0
    private var tokens: [HTMLToken] = []

    init(_ input: String) {
        characters = Array(input)
    }

    mutating func scanTokens() -> [HTMLToken] {
        while index < characters.count {
            if characters[index] == "<", let token = scanMarkup() {
                tokens.append(token)
            } else if index < characters.count {
                let start = index
                while index < characters.count, characters[index] != "<" {
                    index += 1
                }
                tokens.append(.text(String(characters[start..<index])))
            }
        }
        return tokens
    }

    /// Returns nil when the caller should continue without emitting a token.
    /// Malformed markup is emitted as text so sanitizer output can escape it.
    private mutating func scanMarkup() -> HTMLToken? {
        if hasPrefix("<!--") {
            consumeUntil("-->")
            return .ignored
        }
        if hasPrefix("<![CDATA[") {
            index += "<![CDATA[".count
            let start = index
            while index < characters.count, !hasPrefix("]]>") { index += 1 }
            let text = String(characters[start..<index])
            consumeUntil("]]>")
            return .text(text)
        }
        if hasPrefix("</") {
            return scanEndTag()
        }
        if hasPrefix("<!") || hasPrefix("<?") {
            consumeTag()
            return .ignored
        }
        guard index + 1 < characters.count, characters[index + 1].isLetter else {
            index += 1
            return .text("<")
        }
        return scanStartTag()
    }

    private mutating func scanEndTag() -> HTMLToken {
        let start = index
        index += 2
        skipWhitespace()
        let name = scanName().lowercased()
        while index < characters.count, characters[index] != ">" { index += 1 }
        if index < characters.count { index += 1 }
        guard !name.isEmpty else {
            return .text(String(characters[start..<index]))
        }
        return .endTag(name: name)
    }

    private mutating func scanStartTag() -> HTMLToken {
        let start = index
        index += 1
        let name = scanName().lowercased()
        var attributes: [HTMLAttribute] = []
        var selfClosing = false
        var terminated = false

        while index < characters.count {
            skipWhitespace()
            guard index < characters.count else { break }
            if characters[index] == ">" {
                index += 1
                terminated = true
                break
            }
            if characters[index] == "/", index + 1 < characters.count,
                characters[index + 1] == ">"
            {
                index += 2
                selfClosing = true
                terminated = true
                break
            }
            let attributeName = scanAttributeName().lowercased()
            if attributeName.isEmpty {
                index += 1
                continue
            }
            skipWhitespace()
            var value = ""
            if index < characters.count, characters[index] == "=" {
                index += 1
                skipWhitespace()
                value = scanAttributeValue()
            }
            if !attributes.contains(where: { $0.name == attributeName }) {
                attributes.append(HTMLAttribute(name: attributeName, value: value))
            }
        }
        guard terminated, !name.isEmpty else {
            return .text(String(characters[start..<index]))
        }
        return .startTag(name: name, attributes: attributes, selfClosing: selfClosing)
    }

    private mutating func scanName() -> String {
        let start = index
        while index < characters.count {
            let character = characters[index]
            guard character.isLetter || character.isNumber || character == "-"
                || character == ":" || character == "_"
            else { break }
            index += 1
        }
        return String(characters[start..<index])
    }

    private mutating func scanAttributeName() -> String {
        let start = index
        while index < characters.count {
            let character = characters[index]
            guard !character.isWhitespace, character != "=", character != ">", character != "/"
            else { break }
            index += 1
        }
        return String(characters[start..<index])
    }

    private mutating func scanAttributeValue() -> String {
        guard index < characters.count else { return "" }
        if characters[index] == "\"" || characters[index] == "'" {
            let quote = characters[index]
            index += 1
            let start = index
            while index < characters.count, characters[index] != quote { index += 1 }
            let value = String(characters[start..<index])
            if index < characters.count { index += 1 }
            return value
        }
        let start = index
        while index < characters.count, !characters[index].isWhitespace,
            characters[index] != ">"
        {
            index += 1
        }
        return String(characters[start..<index])
    }

    private mutating func skipWhitespace() {
        while index < characters.count, characters[index].isWhitespace { index += 1 }
    }

    private mutating func consumeTag() {
        var quote: Character?
        while index < characters.count {
            let character = characters[index]
            index += 1
            if let active = quote {
                if character == active { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return
            }
        }
    }

    private mutating func consumeUntil(_ terminator: String) {
        while index < characters.count, !hasPrefix(terminator) { index += 1 }
        if index < characters.count { index += terminator.count }
    }

    private func hasPrefix(_ value: String) -> Bool {
        let candidate = Array(value)
        guard index + candidate.count <= characters.count else { return false }
        return Array(characters[index..<(index + candidate.count)]) == candidate
    }
}

enum HTMLEntities {
    static func decode(_ input: String) -> String {
        let characters = Array(input)
        var output = ""
        var index = 0
        while index < characters.count {
            guard characters[index] == "&", let semicolon = findSemicolon(in: characters, from: index + 1) else {
                output.append(characters[index])
                index += 1
                continue
            }
            let entity = String(characters[(index + 1)..<semicolon])
            if let decoded = decodeEntity(entity) {
                output += decoded
                index = semicolon + 1
            } else {
                output.append(characters[index])
                index += 1
            }
        }
        return output
    }

    static func escapePreservingEntities(_ input: String) -> String {
        let characters = Array(input)
        var output = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "&", let semicolon = findSemicolon(in: characters, from: index + 1) {
                let entity = String(characters[(index + 1)..<semicolon])
                if isEntityShape(entity) {
                    output += String(characters[index...semicolon])
                    index = semicolon + 1
                    continue
                }
            }
            switch character {
            case "&": output += "&amp;"
            case "<": output += "&lt;"
            case ">": output += "&gt;"
            default: output.append(character)
            }
            index += 1
        }
        return output
    }

    static func escapeAttribute(_ input: String) -> String {
        var output = ""
        for character in decode(input) {
            switch character {
            case "&": output += "&amp;"
            case "<": output += "&lt;"
            case ">": output += "&gt;"
            case "\"": output += "&quot;"
            default: output.append(character)
            }
        }
        return output
    }

    private static func findSemicolon(in characters: [Character], from start: Int) -> Int? {
        var index = start
        while index < characters.count, index - start <= 32 {
            if characters[index] == ";" { return index }
            if characters[index].isWhitespace || characters[index] == "&" || characters[index] == "<" {
                return nil
            }
            index += 1
        }
        return nil
    }

    private static func isEntityShape(_ entity: String) -> Bool {
        if entity.hasPrefix("#") {
            let digits = entity.dropFirst(entity.hasPrefix("#x") || entity.hasPrefix("#X") ? 2 : 1)
            return !digits.isEmpty && digits.allSatisfy(\.isHexDigit)
        }
        return !entity.isEmpty && entity.allSatisfy { $0.isLetter || $0.isNumber }
    }

    private static func decodeEntity(_ entity: String) -> String? {
        if entity.hasPrefix("#") {
            let hexadecimal = entity.hasPrefix("#x") || entity.hasPrefix("#X")
            let digits = entity.dropFirst(hexadecimal ? 2 : 1)
            guard let value = UInt32(digits, radix: hexadecimal ? 16 : 10),
                let scalar = UnicodeScalar(value), !(0xD800...0xDFFF).contains(value)
            else { return nil }
            return String(scalar)
        }
        return named[entity]
    }

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "ensp": "\u{2002}", "emsp": "\u{2003}",
        "thinsp": "\u{2009}", "ndash": "–", "mdash": "—", "hellip": "…",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "laquo": "«", "raquo": "»", "copy": "©", "reg": "®", "trade": "™",
        "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "deg": "°",
        "plusmn": "±", "times": "×", "divide": "÷", "micro": "µ",
        "para": "¶", "sect": "§", "middot": "·", "bull": "•",
        "eacute": "é", "egrave": "è", "ecirc": "ê", "euml": "ë",
        "agrave": "à", "acirc": "â", "ccedil": "ç", "icirc": "î",
        "ocirc": "ô", "ugrave": "ù", "ucirc": "û", "uuml": "ü",
        "Eacute": "É", "Egrave": "È", "Agrave": "À", "Ccedil": "Ç"
    ]
}
