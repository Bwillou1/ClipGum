import Foundation

enum JSONFormattingError: LocalizedError, Equatable {
    case invalidDocument

    var errorDescription: String? {
        "JSON Format accepts one valid JSON object or array. The deterministic result was preserved."
    }
}

struct JSONFormattingService {
    func format(_ input: String) throws -> String {
        do {
            let object = try JSONSerialization.jsonObject(with: Data(input.utf8))
            guard JSONSerialization.isValidJSONObject(object) else {
                throw JSONFormattingError.invalidDocument
            }
            let data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            guard let output = String(data: data, encoding: .utf8) else {
                throw JSONFormattingError.invalidDocument
            }
            return output
        } catch let error as JSONFormattingError {
            throw error
        } catch {
            throw JSONFormattingError.invalidDocument
        }
    }
}
