import Foundation

enum TableSourceKind: String, Equatable, Sendable {
    case html
    case tsv
    case csv
    case semicolonCSV
    case markdown
    case alignedASCII

    var title: String {
        switch self {
        case .html: return "HTML table"
        case .tsv: return "Excel / TSV"
        case .csv: return "CSV"
        case .semicolonCSV: return "Semicolon CSV"
        case .markdown: return "Markdown"
        case .alignedASCII: return "Aligned text"
        }
    }
}

struct TableDocument: Equatable, Sendable {
    let rows: [[String]]
    let source: TableSourceKind

    var detection: TableDetection? {
        guard let columns = rows.first?.count, columns > 0,
            rows.allSatisfy({ $0.count == columns })
        else { return nil }
        return TableDetection(source: source, rowCount: rows.count, columnCount: columns)
    }
}

struct TableDetection: Equatable, Sendable {
    let source: TableSourceKind
    let rowCount: Int
    let columnCount: Int
}

enum TableOutputFormat: String, CaseIterable, Identifiable, Sendable {
    case csv
    case tsv
    case markdown

    var id: String { rawValue }
    var title: String {
        switch self {
        case .csv: return "CSV"
        case .tsv: return "TSV"
        case .markdown: return "Markdown"
        }
    }
}

enum TableDelimiter: String, CaseIterable, Identifiable, Sendable {
    case comma
    case semicolon

    var id: String { rawValue }
    var title: String {
        switch self {
        case .comma: return "Comma (,)"
        case .semicolon: return "Semicolon (;)"
        }
    }

    var character: Character {
        switch self {
        case .comma: return ","
        case .semicolon: return ";"
        }
    }
}

struct TableConversionOptions: Equatable, Sendable {
    var format: TableOutputFormat = .csv
    var delimiter: TableDelimiter = .comma
}

enum TableWorkflowError: LocalizedError, Equatable, Sendable {
    case noTable
    case inconsistentColumns
    case unsupportedSpan
    case nestedOrMultipleTables
    case malformedDelimitedText
    case inputTooLarge

    var errorDescription: String? {
        switch self {
        case .noTable:
            return "No consistently aligned HTML, TSV, CSV, Markdown, or ASCII table was detected."
        case .inconsistentColumns:
            return "Every detected table row must have the same nonzero column count. No cells were inferred or repaired."
        case .unsupportedSpan:
            return "HTML rowspan/colspan values other than 1 are rejected to avoid duplicating or inventing cells."
        case .nestedOrMultipleTables:
            return "Select one non-nested HTML table at a time. ClipGum will not merge table structures."
        case .malformedDelimitedText:
            return "The delimited table has an unmatched quote or invalid characters after a closing quote."
        case .inputTooLarge:
            return "Table input exceeds the 4 MiB, 10,000-row, or 256-column safety boundary."
        }
    }
}
