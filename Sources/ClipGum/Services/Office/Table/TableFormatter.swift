import Foundation

struct TableFormatter {
    func format(_ table: TableDocument, options: TableConversionOptions) throws -> String {
        guard table.detection != nil else { throw TableWorkflowError.inconsistentColumns }
        switch options.format {
        case .csv:
            return delimited(
                table.rows,
                delimiter: options.delimiter.character,
                recordSeparator: "\r\n",
                quoteCommaOutsideDelimiter: true
            )
        case .tsv:
            return delimited(
                table.rows,
                delimiter: "\t",
                recordSeparator: "\n",
                quoteCommaOutsideDelimiter: false
            )
        case .markdown:
            return markdown(table.rows)
        }
    }

    private func delimited(
        _ rows: [[String]],
        delimiter: Character,
        recordSeparator: String,
        quoteCommaOutsideDelimiter: Bool
    ) -> String {
        rows.map { row in
            row.map { field in
                quote(
                    field,
                    delimiter: delimiter,
                    quoteCommaOutsideDelimiter: quoteCommaOutsideDelimiter
                )
            }.joined(separator: String(delimiter))
        }.joined(separator: recordSeparator)
    }

    private func quote(
        _ field: String,
        delimiter: Character,
        quoteCommaOutsideDelimiter: Bool
    ) -> String {
        let needsQuotes = field.contains(delimiter) || field.contains("\"")
            || field.contains("\n") || field.contains("\r")
            || (quoteCommaOutsideDelimiter && field.contains(","))
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func markdown(_ rows: [[String]]) -> String {
        guard let header = rows.first else { return "" }
        let headerLine = markdownRow(header)
        let separator = "| " + header.map { _ in "---" }.joined(separator: " | ") + " |"
        let body = rows.dropFirst().map(markdownRow)
        return ([headerLine, separator] + body).joined(separator: "\n")
    }

    private func markdownRow(_ row: [String]) -> String {
        "| " + row.map { field in
            field.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "|", with: "\\|")
                .replacingOccurrences(of: "\r\n", with: "<br>")
                .replacingOccurrences(of: "\n", with: "<br>")
                .replacingOccurrences(of: "\r", with: "<br>")
        }.joined(separator: " | ") + " |"
    }
}
