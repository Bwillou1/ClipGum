import Foundation

/// Compatibility error for the Phase 2 synchronous API. New developer actions
/// use JSONSyntaxError directly to retain its exact line and column.
enum JSONFormattingError: LocalizedError, Equatable {
    case invalidDocument

    var errorDescription: String? {
        "JSON Format accepts one valid JSON object or array. The deterministic result was preserved."
    }
}

struct JSONFormattingService {
    func format(_ input: String) throws -> String {
        do {
            let value = try JSONParser.parse(input)
            switch value {
            case .object, .array:
                return JSONRenderer.render(value, indentation: .twoSpaces)
            case .string, .number, .bool, .null:
                throw JSONFormattingError.invalidDocument
            }
        } catch let error as JSONFormattingError {
            throw error
        } catch {
            throw JSONFormattingError.invalidDocument
        }
    }
}
