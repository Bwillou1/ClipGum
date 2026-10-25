import Foundation

struct TableExtractionService {
    static let maximumInputUTF8Bytes = 4 * 1_024 * 1_024
    static let maximumRows = 10_000
    static let maximumColumns = 256

    private let scanner = HTMLScanner()
    private let delimitedParser = DelimitedTextParser()

    func detect(document: PasteboardDocument?, plainText: String) -> TableDetection? {
        guard let table = try? extract(document: document, plainText: plainText) else { return nil }
        return table.detection
    }

    func extract(document: PasteboardDocument?, plainText: String) throws -> TableDocument {
        guard plainText.utf8.count <= Self.maximumInputUTF8Bytes,
            (document?.html?.utf8.count ?? 0) <= Self.maximumInputUTF8Bytes
        else { throw TableWorkflowError.inputTooLarge }

        if let html = document?.html, html.lowercased().contains("<table") {
            return try extractHTML(html)
        }
        if plainText.lowercased().contains("<table") {
            return try extractHTML(plainText)
        }
        return try extractPlain(plainText)
    }

    private func extractPlain(_ input: String) throws -> TableDocument {
        if input.contains("\t") {
            let rows = try delimitedParser.parse(input, delimiter: "\t")
            return try validated(rows, source: .tsv, allowSingleRow: true)
        }
        if looksLikeMarkdown(input) {
            let rows = try markdownRows(input)
            return try validated(rows, source: .markdown, allowSingleRow: false)
        }

        var delimitedCandidates: [TableDocument] = []
        for (delimiter, source) in [(Character(","), TableSourceKind.csv), (Character(";"), .semicolonCSV)] {
            guard input.contains(delimiter), let rows = try? delimitedParser.parse(input, delimiter: delimiter),
                let table = try? validated(rows, source: source, allowSingleRow: false)
            else { continue }
            delimitedCandidates.append(table)
        }
        if let best = delimitedCandidates.max(by: {
            ($0.rows.first?.count ?? 0) < ($1.rows.first?.count ?? 0)
        }) {
            return best
        }
        return try validated(asciiRows(input), source: .alignedASCII, allowSingleRow: false)
    }

    private func extractHTML(_ input: String) throws -> TableDocument {
        let tokens = try scanner.scan(input)
        var rows: [[String]] = []
        var row: [String] = []
        var cell: String?
        var insideTable = false
        var finishedTable = false
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
            if case .startTag(let name, _, let selfClosing) = token,
                ["script", "style", "head"].contains(name)
            {
                if !selfClosing { suppressed = (name, 1) }
                continue
            }
            switch token {
            case .startTag(let name, let attributes, _):
                if name == "table" {
                    if insideTable || finishedTable { throw TableWorkflowError.nestedOrMultipleTables }
                    insideTable = true
                }
                guard insideTable else { continue }
                if name == "td" || name == "th" {
                    try rejectSpans(attributes)
                    guard cell == nil else { throw TableWorkflowError.inconsistentColumns }
                    cell = ""
                } else if name == "tr" {
                    guard cell == nil else { throw TableWorkflowError.inconsistentColumns }
                    if !row.isEmpty {
                        rows.append(row)
                        row = []
                    }
                } else if name == "br", cell != nil {
                    cell = (cell ?? "") + "\n"
                } else if ["p", "div"].contains(name), cell != nil {
                    cell = (cell ?? "") + " "
                }
            case .endTag(let name):
                guard insideTable else { continue }
                if name == "td" || name == "th" {
                    guard let value = cell else { throw TableWorkflowError.inconsistentColumns }
                    row.append(normalizeCell(value))
                    cell = nil
                } else if name == "tr" {
                    if cell != nil { throw TableWorkflowError.inconsistentColumns }
                    if !row.isEmpty {
                        rows.append(row)
                        row = []
                    }
                } else if name == "table" {
                    guard cell == nil else { throw TableWorkflowError.inconsistentColumns }
                    if !row.isEmpty {
                        rows.append(row)
                        row = []
                    }
                    insideTable = false
                    finishedTable = true
                }
            case .text(let text):
                if cell != nil { cell = (cell ?? "") + HTMLEntities.decode(text) }
            case .ignored:
                continue
            }
        }
        if insideTable { throw TableWorkflowError.inconsistentColumns }
        return try validated(rows, source: .html, allowSingleRow: true)
    }

    private func rejectSpans(_ attributes: [HTMLAttribute]) throws {
        for attribute in attributes where attribute.name == "colspan" || attribute.name == "rowspan" {
            let value = HTMLEntities.decode(attribute.value).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty && value != "1" { throw TableWorkflowError.unsupportedSpan }
        }
    }

    private func normalizeCell(_ input: String) -> String {
        var output = ""
        var previousWasSpace = false
        for character in input {
            if character == "\n" {
                while output.last == " " { output.removeLast() }
                output += "\n"
                previousWasSpace = false
            } else if character == "\u{00A0}" {
                output.append(character)
                previousWasSpace = false
            } else if character.isWhitespace {
                if !previousWasSpace, !output.isEmpty, output.last != "\n" { output += " " }
                previousWasSpace = true
            } else {
                output.append(character)
                previousWasSpace = false
            }
        }
        return output.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: " "))
        }.joined(separator: "\n").trimmingCharacters(in: CharacterSet(charactersIn: " \n"))
    }

    private func validated(
        _ rows: [[String]],
        source: TableSourceKind,
        allowSingleRow: Bool
    ) throws -> TableDocument {
        guard !rows.isEmpty, allowSingleRow || rows.count >= 2,
            let columns = rows.first?.count, columns > 1
        else { throw TableWorkflowError.noTable }
        guard rows.count <= Self.maximumRows, columns <= Self.maximumColumns else {
            throw TableWorkflowError.inputTooLarge
        }
        guard rows.allSatisfy({ $0.count == columns }) else {
            throw TableWorkflowError.inconsistentColumns
        }
        return TableDocument(rows: rows, source: source)
    }

    private func looksLikeMarkdown(_ input: String) -> Bool {
        let lines = input.components(separatedBy: .newlines).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return lines.count >= 2 && lines.allSatisfy {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("|")
        }
    }

    private func markdownRows(_ input: String) throws -> [[String]] {
        let lines = input.components(separatedBy: .newlines).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        var rows = try lines.map(markdownCells)
        if rows.count >= 2, isMarkdownSeparator(rows[1]) {
            rows.remove(at: 1)
        }
        return rows
    }

    private func markdownCells(_ line: String) throws -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|"), !text.hasSuffix("\\|") { text.removeLast() }
        var cells: [String] = []
        var cell = ""
        var escaped = false
        for character in text {
            if escaped {
                if character == "|" || character == "\\" {
                    cell.append(character)
                } else {
                    cell.append("\\")
                    cell.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else {
                cell.append(character)
            }
        }
        if escaped { cell.append("\\") }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private func isMarkdownSeparator(_ cells: [String]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { cell in
            let compact = cell.replacingOccurrences(of: " ", with: "")
            return compact.contains("-") && compact.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private func asciiRows(_ input: String) throws -> [[String]] {
        let lines = input.components(separatedBy: .newlines).filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard lines.count >= 2 else { throw TableWorkflowError.noTable }
        let rows = lines.map(splitAlignedRow)
        guard rows.allSatisfy({ $0.count > 1 }) else { throw TableWorkflowError.noTable }
        return rows
    }

    private func splitAlignedRow(_ line: String) -> [String] {
        var cells: [String] = []
        var cell = ""
        var spaces = 0
        for character in line.trimmingCharacters(in: .whitespaces) {
            if character == " " {
                spaces += 1
                continue
            }
            if spaces >= 2 {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
            } else if spaces == 1 {
                cell += " "
            }
            spaces = 0
            cell.append(character)
        }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        return cells
    }
}
