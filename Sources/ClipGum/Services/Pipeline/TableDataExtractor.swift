import Foundation

enum TableDataError: Error, Equatable {
    case unsupportedTable
    case inconsistentColumns
}

/// Extracts the exact source matrix used to verify an LLM's CSV response.
/// Unknown table layouts are rejected rather than "repaired" heuristically.
struct TableDataExtractor {
    func rows(from input: String) throws -> [[String]] {
        let normalized = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        if lines.last == "" {
            lines.removeLast()
        }
        guard !lines.isEmpty else {
            throw TableDataError.unsupportedTable
        }

        let rows: [[String]]
        if lines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") }) {
            rows = lines.enumerated().compactMap { index, line in
                let cells = markdownCells(line)
                if index == 1, isMarkdownSeparator(cells) {
                    return nil
                }
                return cells
            }
        } else if lines.contains(where: { $0.contains("\t") }) {
            rows = lines.map {
                $0.components(separatedBy: "\t")
            }
        } else {
            throw TableDataError.unsupportedTable
        }

        guard let columnCount = rows.first?.count, columnCount > 0,
            rows.allSatisfy({ $0.count == columnCount })
        else {
            throw TableDataError.inconsistentColumns
        }
        return rows
    }

    private func markdownCells(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") {
            text.removeFirst()
        }
        if text.hasSuffix("|") {
            text.removeLast()
        }
        return text.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private func isMarkdownSeparator(_ cells: [String]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { cell in
            let compact = cell.replacingOccurrences(of: " ", with: "")
            return compact.contains("-")
                && compact.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }
}
