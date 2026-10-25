import Foundation

/// Removes only known tracking query keys from HTTP(S) URLs.
///
/// URLComponents is used for validation, never for reconstruction. Surviving
/// names, values, percent escapes, order, duplicates, paths, and fragments stay
/// byte-for-byte identical.
struct URLTrackingCleaner {
    private static let exactTrackingNames: Set<String> = [
        "fbclid",
        "gclid",
        "dclid",
        "gbraid",
        "wbraid",
        "msclkid",
        "mc_cid",
        "mc_eid",
        "mkt_tok"
    ]

    private static let urlExpression: NSRegularExpression = {
        // Candidates are bounded before validation; trailing prose punctuation
        // is separated below so it cannot become part of a removed value.
        try! NSRegularExpression(
            pattern: #"(?i)\bhttps?://[^\s<>"'“”‘’]+"#
        )
    }()

    func stripTrackingParameters(in input: String) -> TransformResult {
        let range = NSRange(input.startIndex..., in: input)
        let matches = Self.urlExpression.matches(in: input, range: range)
        guard !matches.isEmpty else {
            return TransformResult(output: input, changeCount: 0)
        }

        return MatchReplacer.apply(to: input, matches: matches) { match, source in
            let candidate = source.substring(with: match.range)
            let (urlPart, punctuation) = Self.separateTrailingPunctuation(from: candidate)
            let result = cleanSingleURL(urlPart)
            guard result.changeCount > 0 else { return nil }
            return MatchReplacement(
                range: match.range,
                text: result.output + punctuation,
                changeCount: result.changeCount
            )
        }
    }

    private func cleanSingleURL(_ input: String) -> TransformResult {
        guard
            Self.hasValidPercentEscapes(input),
            let components = URLComponents(string: input),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = components.host,
            !host.isEmpty
        else {
            // Invalid and ambiguous URLs are intentionally left untouched.
            return TransformResult(output: input, changeCount: 0)
        }

        guard let questionMark = input.firstIndex(of: "?") else {
            return TransformResult(output: input, changeCount: 0)
        }
        if let fragmentStart = input.firstIndex(of: "#"), questionMark > fragmentStart {
            return TransformResult(output: input, changeCount: 0)
        }

        let base = String(input[..<questionMark])
        let afterQuestionMark = input.index(after: questionMark)
        let remainder = String(input[afterQuestionMark...])
        let query: String
        let fragment: String

        if let hash = remainder.firstIndex(of: "#") {
            query = String(remainder[..<hash])
            fragment = String(remainder[hash...])
        } else {
            query = remainder
            fragment = ""
        }

        guard !query.isEmpty else {
            return TransformResult(output: input, changeCount: 0)
        }

        var removedCount = 0
        let fields = query.split(separator: "&", omittingEmptySubsequences: false)
        let survivingFields = fields.filter { field in
            let encodedName = field.firstIndex(of: "=").map { field[..<$0] } ?? field

            guard let name = Self.decodeQueryName(String(encodedName)) else {
                return true
            }

            if Self.isTrackingName(name) {
                removedCount += 1
                return false
            }
            return true
        }

        guard removedCount > 0 else {
            return TransformResult(output: input, changeCount: 0)
        }

        let survivingQuery = survivingFields.joined(separator: "&")
        let cleaned = survivingQuery.isEmpty
            ? base + fragment
            : base + "?" + survivingQuery + fragment

        return TransformResult(output: cleaned, changeCount: removedCount)
    }

    private static func isTrackingName(_ decodedName: String) -> Bool {
        let normalized = decodedName.lowercased()
        return normalized.hasPrefix("utm_") || exactTrackingNames.contains(normalized)
    }

    private static func decodeQueryName(_ name: String) -> String? {
        let plusDecoded = name.replacingOccurrences(of: "+", with: " ")
        // A malformed escape must not turn into a different key accidentally.
        return plusDecoded.removingPercentEncoding
    }

    private static func hasValidPercentEscapes(_ input: String) -> Bool {
        let scalars = Array(input.unicodeScalars)
        let hexadecimal = Set("0123456789abcdefABCDEF".unicodeScalars)

        for index in scalars.indices where scalars[index] == "%" {
            guard
                index + 2 < scalars.count,
                hexadecimal.contains(scalars[index + 1]),
                hexadecimal.contains(scalars[index + 2])
            else {
                return false
            }
        }
        return true
    }

    private static func separateTrailingPunctuation(from candidate: String) -> (String, String) {
        var url = candidate
        var punctuation = ""
        let sentencePunctuation: Set<Character> = [".", ",", ";", ":", "!", "?"]

        while let last = url.last, sentencePunctuation.contains(last) {
            punctuation.insert(last, at: punctuation.startIndex)
            url.removeLast()
        }

        let bracketPairs: [(open: Character, close: Character)] = [
            ("(", ")"), ("[", "]"), ("{", "}")
        ]
        for pair in bracketPairs {
            while
                url.last == pair.close,
                url.filter({ $0 == pair.close }).count > url.filter({ $0 == pair.open }).count
            {
                punctuation.insert(pair.close, at: punctuation.startIndex)
                url.removeLast()
            }
        }

        return (url, punctuation)
    }
}
