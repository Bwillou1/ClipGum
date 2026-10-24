import Foundation

/// Semantic allowlist inspired by SwiftSoup's Cleaner/Safelist separation.
/// Styling containers are unwrapped; script/style/head content is discarded.
struct HTMLSemanticProcessor {
    private let scanner = HTMLScanner()

    private static let allowedTags: Set<String> = [
        "strong", "b", "em", "i", "a", "h1", "h2", "h3", "ul", "ol", "li",
        "p", "br", "blockquote", "table", "thead", "tbody", "tfoot", "tr",
        "th", "td", "caption"
    ]
    private static let voidTags: Set<String> = ["br"]
    private static let suppressedTags: Set<String> = ["script", "style", "head"]
    private static let blockTags: Set<String> = [
        "p", "div", "section", "article", "h1", "h2", "h3", "blockquote",
        "ul", "ol", "table", "thead", "tbody", "tfoot", "caption"
    ]

    func sanitizedHTML(from input: String) throws -> String {
        let tokens = try scanner.scan(input)
        var output = ""
        var openTags: [String] = []
        var suppressed: (name: String, depth: Int)?

        for token in tokens {
            if var active = suppressed {
                switch token {
                case .startTag(let name, _, let selfClosing) where name == active.name && !selfClosing:
                    active.depth += 1
                    suppressed = active
                case .endTag(let name) where name == active.name:
                    active.depth -= 1
                    suppressed = active.depth == 0 ? nil : active
                default:
                    break
                }
                continue
            }

            switch token {
            case .text(let text):
                output += HTMLEntities.escapePreservingEntities(text)
            case .ignored:
                continue
            case .startTag(let name, let attributes, let selfClosing):
                if Self.suppressedTags.contains(name) {
                    if !selfClosing { suppressed = (name, 1) }
                    continue
                }
                guard Self.allowedTags.contains(name) else { continue }
                if Self.voidTags.contains(name) {
                    output += "<\(name)>"
                    continue
                }
                output += "<\(name)"
                if name == "a", let href = attributes.first(where: { $0.name == "href" }),
                    isSafeHyperlink(href.value)
                {
                    output += " href=\"\(HTMLEntities.escapeAttribute(href.value))\""
                }
                output += ">"
                openTags.append(name)
                if selfClosing {
                    output += "</\(name)>"
                    openTags.removeLast()
                }
            case .endTag(let name):
                guard Self.allowedTags.contains(name), !Self.voidTags.contains(name),
                    let match = openTags.lastIndex(of: name)
                else { continue }
                while openTags.count > match + 1 {
                    output += "</\(openTags.removeLast())>"
                }
                output += "</\(openTags.removeLast())>"
            }
        }
        while let tag = openTags.popLast() {
            output += "</\(tag)>"
        }
        return output
    }

    func plainText(from input: String) throws -> String {
        let tokens = try scanner.scan(input)
        var builder = PlainTextBuilder()
        var suppressed: (name: String, depth: Int)?

        for token in tokens {
            if var active = suppressed {
                switch token {
                case .startTag(let name, _, let selfClosing) where name == active.name && !selfClosing:
                    active.depth += 1
                    suppressed = active
                case .endTag(let name) where name == active.name:
                    active.depth -= 1
                    suppressed = active.depth == 0 ? nil : active
                default:
                    break
                }
                continue
            }

            switch token {
            case .text(let text):
                builder.appendText(HTMLEntities.decode(text))
            case .ignored:
                continue
            case .startTag(let name, _, let selfClosing):
                if Self.suppressedTags.contains(name) {
                    if !selfClosing { suppressed = (name, 1) }
                } else if name == "br" {
                    builder.newline()
                } else if name == "li" {
                    builder.newline()
                    builder.appendLiteral("- ")
                } else if name == "tr" {
                    builder.newline()
                } else if name == "td" || name == "th" {
                    builder.cellBoundary()
                } else if Self.blockTags.contains(name) {
                    builder.newline()
                }
            case .endTag(let name):
                if name == "tr" || name == "li" || Self.blockTags.contains(name) {
                    builder.newline()
                }
            }
        }
        return builder.finish()
    }

    private func isSafeHyperlink(_ value: String) -> Bool {
        let decoded = HTMLEntities.decode(value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decoded.isEmpty,
            !decoded.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
        else { return false }
        let lower = decoded.lowercased()
        if let colon = lower.firstIndex(of: ":") {
            let scheme = String(lower[..<colon])
            return ["http", "https", "mailto", "tel"].contains(scheme)
        }
        return true
    }
}

private struct PlainTextBuilder {
    private var output = ""

    mutating func appendText(_ text: String) {
        for character in text {
            if character == "\u{00A0}" {
                appendLiteral("\u{00A0}")
            } else if character.isWhitespace {
                appendLiteral(" ")
            } else {
                output.append(character)
            }
        }
    }

    mutating func appendLiteral(_ literal: String) {
        if literal == " ", output.isEmpty || output.last == " " || output.last == "\n" {
            return
        }
        output += literal
    }

    mutating func cellBoundary() {
        guard !output.isEmpty, output.last != "\n", output.last != "\t" else { return }
        trimTrailingSpaces()
        output += "\t"
    }

    mutating func newline() {
        trimTrailingSpaces()
        trimTrailingTabs()
        guard !output.isEmpty, output.last != "\n" else { return }
        output += "\n"
    }

    func finish() -> String {
        var lines = output.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        var result: [String] = []
        var previousBlank = false
        for line in lines {
            let blank = line.isEmpty
            if blank, previousBlank { continue }
            result.append(line)
            previousBlank = blank
        }
        while result.first == "" { result.removeFirst() }
        while result.last == "" { result.removeLast() }
        return result.joined(separator: "\n")
    }

    private mutating func trimTrailingSpaces() {
        while output.last == " " { output.removeLast() }
    }

    private mutating func trimTrailingTabs() {
        while output.last == "\t" { output.removeLast() }
    }
}
