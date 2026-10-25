import Foundation

enum CSVError: Error, Equatable {
    case malformed
}

/// Small RFC 4180-style parser used for validation, not model generation.
/// Supports quoted commas, doubled quotes, CR/LF inside quotes, and CRLF rows.
struct CSVDocument: Equatable, Sendable {
    let rows: [[String]]

    static func parse(_ input: String) throws -> CSVDocument {
        guard !input.isEmpty else {
            return CSVDocument(rows: [])
        }
        let characters = Array(input)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var justClosedQuote = false
        var lastWasRecordSeparator = false
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                    justClosedQuote = true
                } else {
                    field.append(character)
                }
                lastWasRecordSeparator = false
                index += 1
                continue
            }

            if character == "," {
                row.append(field)
                field = ""
                justClosedQuote = false
                lastWasRecordSeparator = false
            } else if character == "\n" || character == "\r" || character == "\r\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                justClosedQuote = false
                lastWasRecordSeparator = true
            } else if character == "\"" {
                guard field.isEmpty, !justClosedQuote else {
                    throw CSVError.malformed
                }
                inQuotes = true
                lastWasRecordSeparator = false
            } else {
                guard !justClosedQuote else {
                    throw CSVError.malformed
                }
                field.append(character)
                lastWasRecordSeparator = false
            }
            index += 1
        }

        guard !inQuotes else {
            throw CSVError.malformed
        }
        if !lastWasRecordSeparator || !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return CSVDocument(rows: rows)
    }
}
