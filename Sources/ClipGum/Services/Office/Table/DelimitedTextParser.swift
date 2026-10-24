import Foundation

/// RFC 4180-style quoting with a configurable single-character delimiter.
/// Record separators inside quoted fields remain cell content.
struct DelimitedTextParser {
    func parse(_ input: String, delimiter: Character) throws -> [[String]] {
        guard !input.isEmpty else { return [] }
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

            if character == delimiter {
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
                    throw TableWorkflowError.malformedDelimitedText
                }
                inQuotes = true
                lastWasRecordSeparator = false
            } else {
                guard !justClosedQuote else {
                    throw TableWorkflowError.malformedDelimitedText
                }
                field.append(character)
                lastWasRecordSeparator = false
            }
            index += 1
        }

        guard !inQuotes else { throw TableWorkflowError.malformedDelimitedText }
        if !lastWasRecordSeparator || !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
