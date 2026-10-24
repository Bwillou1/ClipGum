import Foundation

/// Stateless JSON workflows. Every operation parses the same native AST;
/// malformed input returns an exact syntax location and never reaches a model.
struct JSONToolingService {
    func parse(_ input: String) throws -> JSONValue {
        try JSONParser.parse(input)
    }

    func validate(_ input: String) -> JSONValidationResult {
        JSONParser.validate(input)
    }

    func format(_ input: String, indentation: JSONIndentation) throws -> String {
        JSONRenderer.render(try parse(input), indentation: indentation)
    }

    func minify(_ input: String) throws -> String {
        JSONRenderer.render(try parse(input), indentation: nil)
    }
}
