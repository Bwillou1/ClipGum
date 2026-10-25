import Foundation

struct InlineDiffSegment: Equatable, Sendable {
    enum Kind: Hashable, Sendable {
        case unchanged
        case insertion
        case removal
    }

    let kind: Kind
    let text: String
}

/// Token/whitespace diff with exact reconstruction. CollectionDifference uses a
/// compact difference rather than an O(n*m) table, which keeps streaming UI work
/// bounded better than a naive LCS implementation.
enum InlineDiff {
    private static let tokenizer = try! NSRegularExpression(
        pattern: #"\s+|[\p{L}\p{N}_]+|[^\s\p{L}\p{N}_]"#
    )

    static func segments(before: String, after: String) -> [InlineDiffSegment] {
        guard before != after else {
            return before.isEmpty ? [] : [InlineDiffSegment(kind: .unchanged, text: before)]
        }
        let oldTokens = tokens(in: before)
        let newTokens = tokens(in: after)
        let difference = newTokens.difference(from: oldTokens)
        var removals: [Int: String] = [:]
        var insertions: [Int: String] = [:]
        for change in difference {
            switch change {
            case .remove(let offset, let value, _):
                removals[offset] = value
            case .insert(let offset, let value, _):
                insertions[offset] = value
            }
        }

        var segments: [InlineDiffSegment] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < oldTokens.count || newIndex < newTokens.count {
            if let removed = removals[oldIndex] {
                append(.removal, removed, to: &segments)
                oldIndex += 1
            } else if let inserted = insertions[newIndex] {
                append(.insertion, inserted, to: &segments)
                newIndex += 1
            } else if oldIndex < oldTokens.count, newIndex < newTokens.count {
                append(.unchanged, oldTokens[oldIndex], to: &segments)
                oldIndex += 1
                newIndex += 1
            } else if oldIndex < oldTokens.count {
                append(.removal, oldTokens[oldIndex], to: &segments)
                oldIndex += 1
            } else {
                append(.insertion, newTokens[newIndex], to: &segments)
                newIndex += 1
            }
        }
        return segments
    }

    static func tokens(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return tokenizer.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else {
                return nil
            }
            return String(text[range])
        }
    }

    private static func append(
        _ kind: InlineDiffSegment.Kind,
        _ text: String,
        to segments: inout [InlineDiffSegment]
    ) {
        if let last = segments.last, last.kind == kind {
            segments[segments.count - 1] = InlineDiffSegment(
                kind: kind,
                text: last.text + text
            )
        } else {
            segments.append(InlineDiffSegment(kind: kind, text: text))
        }
    }
}
