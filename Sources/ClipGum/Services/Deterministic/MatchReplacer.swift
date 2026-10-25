import Foundation

struct MatchReplacement {
    let range: NSRange
    let text: String
    let changeCount: Int
}

/// Applies non-overlapping NSRegularExpression edits in one forward pass.
/// Ranges remain in the original string's UTF-16 coordinate space; skipped
/// candidates are retained exactly when the next unchanged span is appended.
enum MatchReplacer {
    static func apply(
        to input: String,
        matches: [NSTextCheckingResult],
        edit: (NSTextCheckingResult, NSString) -> MatchReplacement?
    ) -> TransformResult {
        let source = input as NSString
        let output = NSMutableString()
        var cursor = 0
        var changeCount = 0

        for match in matches {
            guard let replacement = edit(match, source) else { continue }
            let range = replacement.range
            guard range.location != NSNotFound, range.length > 0,
                  range.location >= cursor, NSMaxRange(range) <= source.length else { continue }
            output.append(source.substring(with: NSRange(
                location: cursor,
                length: range.location - cursor
            )))
            output.append(replacement.text)
            cursor = NSMaxRange(range)
            changeCount += replacement.changeCount
        }

        guard changeCount > 0 else {
            return TransformResult(output: input, changeCount: 0)
        }
        output.append(source.substring(from: cursor))
        return TransformResult(output: output as String, changeCount: changeCount)
    }
}
