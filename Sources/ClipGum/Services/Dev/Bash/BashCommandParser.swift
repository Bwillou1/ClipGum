import Foundation

enum ShellTokenKind: Equatable, Sendable {
    case word
    case pipeline
    case conjunction
    case sequence
    case redirect
    case comment
    case otherOperator
}

struct ShellToken: Equatable, Sendable {
    let kind: ShellTokenKind
    let text: String
}

struct BashSyntaxError: LocalizedError, Equatable, Sendable {
    let message: String
    let line: Int
    let column: Int

    var errorDescription: String? {
        "Shell parse warning at line \(line), column \(column): \(message)"
    }
}

struct BashParseResult: Equatable, Sendable {
    let tokens: [ShellToken]
    let error: BashSyntaxError?
}

/// Shell-inspired lexer used for inspection only. It performs no expansion,
/// subprocess launch, file access, or evaluation of command substitutions.
struct BashCommandParser {
    func parse(_ input: String) -> BashParseResult {
        var scanner = Scanner(input)
        return scanner.scan()
    }
}

private struct Scanner {
    private let characters: [Character]
    private var index = 0
    private var line = 1
    private var column = 1
    private var tokens: [ShellToken] = []
    private var parseError: BashSyntaxError?

    init(_ input: String) {
        characters = Array(input)
    }

    mutating func scan() -> BashParseResult {
        while index < characters.count {
            let character = characters[index]
            if character == " " || character == "\t" || character == "\r" {
                advance()
            } else if character == "\n" {
                append(.sequence, "\n")
                advance()
            } else if character == "#" {
                append(.comment, String(characters[index...]))
                index = characters.count
            } else if let operation = operatorAtCursor() {
                append(kind(for: operation), operation)
                for _ in operation { advance() }
            } else {
                tokens.append(ShellToken(kind: .word, text: scanWord()))
            }
        }
        return BashParseResult(tokens: tokens, error: parseError)
    }

    private mutating func scanWord() -> String {
        var output = ""
        var quote: Character?
        while index < characters.count {
            let character = characters[index]
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                    advance()
                } else if character == "\\", activeQuote == "\"", index + 1 < characters.count {
                    advance()
                    output.append(characters[index])
                    advance()
                } else {
                    output.append(character)
                    advance()
                }
                continue
            }
            if character == "'" || character == "\"" {
                quote = character
                advance()
            } else if character == "\\" {
                advance()
                guard index < characters.count else {
                    setError("Trailing escape character.")
                    return output
                }
                output.append(characters[index])
                advance()
            } else if character == " " || character == "\t" || character == "\r"
                || character == "\n" || operatorAtCursor() != nil
            {
                break
            } else {
                output.append(character)
                advance()
            }
        }
        if quote != nil {
            setError("Unterminated quoted string; safety checks used the partial token stream.")
        }
        return output
    }

    private func operatorAtCursor() -> String? {
        let remaining = String(characters[index...])
        return ["2>>", "2>", "&&", "||", ">>", "<<", "|&", "&>", "|", "&", ";", ">", "<"]
            .first { remaining.hasPrefix($0) }
    }

    private func kind(for operation: String) -> ShellTokenKind {
        switch operation {
        case "|", "|&": return .pipeline
        case "&&", "||": return .conjunction
        case ";", "&": return .sequence
        case ">", ">>", "<", "<<", "2>", "2>>", "&>": return .redirect
        default: return .otherOperator
        }
    }

    private mutating func append(_ kind: ShellTokenKind, _ text: String) {
        tokens.append(ShellToken(kind: kind, text: text))
    }

    private mutating func advance() {
        if characters[index] == "\n" {
            line += 1
            column = 1
        } else {
            column += 1
        }
        index += 1
    }

    private mutating func setError(_ message: String) {
        guard parseError == nil else { return }
        parseError = BashSyntaxError(message: message, line: line, column: column)
    }
}
