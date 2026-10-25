import Foundation

/// Repairs visual line wrapping without inventing paragraph boundaries.
/// Blank-line-separated blocks remain separated by exactly two newlines.
struct PDFArtifactRepair {
    func repair(_ input: String) -> String {
        let normalized = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var paragraphs: [[String]] = []
        var current: [String] = []

        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty {
                    paragraphs.append(current)
                    current = []
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs.map(repairParagraph).joined(separator: "\n\n")
    }

    private func repairParagraph(_ lines: [String]) -> String {
        guard let first = lines.first else { return "" }
        var output = first.trimmingCharacters(in: .whitespaces)
        for rawLine in lines.dropFirst() {
            let next = rawLine.trimmingCharacters(in: .whitespaces)
            guard !next.isEmpty else { continue }
            if isListStart(next) {
                output += "\n" + next
                continue
            }
            if endsWithSoftHyphen(output), let first = next.first, first.isLetter {
                output.removeLast()
                output += next
            } else if shouldJoinWithoutSpace(output, next) {
                output += next
            } else {
                output += " " + next
            }
        }
        return output
    }

    private func endsWithSoftHyphen(_ text: String) -> Bool {
        guard text.last == "-", text.count >= 2 else { return false }
        let previous = text.index(text.endIndex, offsetBy: -2)
        return text[previous].isLetter
    }

    private func shouldJoinWithoutSpace(_ current: String, _ next: String) -> Bool {
        guard let first = next.first, let last = current.last else { return true }
        if [".", ",", ")", "]", "}", "%", "»"].contains(first) { return true }
        return ["(", "[", "{", "/", "«"].contains(last)
    }

    private func isListStart(_ text: String) -> Bool {
        if let first = text.first, text.count >= 2, ["-", "•", "*"].contains(first),
            text.dropFirst().first?.isWhitespace == true
        {
            return true
        }
        var sawDigit = false
        for character in text {
            if character.isNumber {
                sawDigit = true
            } else if character == ".", sawDigit {
                return text.drop(while: { $0.isNumber }).dropFirst().first?.isWhitespace == true
            } else {
                return false
            }
        }
        return false
    }
}
