import Foundation

/// Conservative regex-based secret reduction, not a complete DLP solution.
/// Each pass is deterministic and replacements never become new rule inputs.
struct SecretRedactor {
    private let placeholder: String

    init(placeholder: String) {
        self.placeholder = placeholder
    }

    private static let awsAccessKey: NSRegularExpression = {
        // AWS's documented 20-character access-key shape, also used by Gitleaks.
        try! NSRegularExpression(
            pattern: #"\b(?:A3T[A-Z0-9]|AKIA|ASIA|ABIA|ACCA)[A-Z2-7]{16}\b"#
        )
    }()

    private static let genericAssignment: NSRegularExpression = {
        // Replace capture group 1 only; keys, quotes, JSON, and punctuation stay.
        // A 12-character floor and explicit key names limit false positives.
        try! NSRegularExpression(
            pattern: #"\b(?:[a-z0-9]+[_.-])*(?:api[_-]?key|access[_-]?token|refresh[_-]?token|auth[_-]?token|client[_-]?secret|secret(?:[_-]?(?:access[_-]?)?key)?|token|passw(?:or)?d|credentials?)\b["']?\s*[:=]\s*["']?([-A-Za-z0-9._~+/=%]{12,})(?=\s|$|[&,#;|)\]\}>]|["'\x60]|\\)"#,
            options: [.caseInsensitive]
        )
    }()

    private static let bearerToken: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"\bBearer[ \t]+([-A-Za-z0-9._~+/=%]{12,})(?=\s|$|[&,#;|)\]\}>]|["'\x60]|\\)"#,
            options: [.caseInsensitive]
        )
    }()

    private static let ipv4Candidate: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(?<![A-Za-z0-9_.])(?:\d{1,3}\.){3}\d{1,3}(?![A-Za-z0-9_.])"#
        )
    }()

    private static let internalHostname: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(?<![A-Za-z0-9_-])(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+(?:internal|intranet|intra|corp|local|lan|home\.arpa)(?![A-Za-z0-9_.-])"#,
            options: [.caseInsensitive]
        )
    }()

    func redactSecrets(in input: String) -> TransformResult {
        var current = input
        var total = 0

        let aws = replaceMatches(in: current, with: Self.awsAccessKey, captureGroup: 0)
        current = aws.output
        total += aws.changeCount

        let assignments = replaceMatches(in: current, with: Self.genericAssignment, captureGroup: 1)
        current = assignments.output
        total += assignments.changeCount

        let bearer = replaceMatches(in: current, with: Self.bearerToken, captureGroup: 1)
        current = bearer.output
        total += bearer.changeCount

        let addresses = replacePrivateIPv4Addresses(in: current)
        current = addresses.output
        total += addresses.changeCount

        let hostnames = replaceMatches(in: current, with: Self.internalHostname, captureGroup: 0)
        current = hostnames.output
        total += hostnames.changeCount

        return TransformResult(output: current, changeCount: total)
    }

    private func replaceMatches(
        in input: String,
        with expression: NSRegularExpression,
        captureGroup: Int
    ) -> TransformResult {
        let matches = expression.matches(
            in: input,
            range: NSRange(input.startIndex..., in: input)
        )
        guard !matches.isEmpty else {
            return TransformResult(output: input, changeCount: 0)
        }

        let output = NSMutableString(string: input)
        var count = 0

        for match in matches.reversed() {
            let range = match.range(at: captureGroup)
            guard range.location != NSNotFound, range.length > 0 else {
                continue
            }
            output.replaceCharacters(in: range, with: placeholder)
            count += 1
        }

        return TransformResult(output: output as String, changeCount: count)
    }

    private func replacePrivateIPv4Addresses(in input: String) -> TransformResult {
        let matches = Self.ipv4Candidate.matches(
            in: input,
            range: NSRange(input.startIndex..., in: input)
        )
        guard !matches.isEmpty else {
            return TransformResult(output: input, changeCount: 0)
        }

        let output = NSMutableString(string: input)
        var count = 0

        for match in matches.reversed() {
            let candidate = output.substring(with: match.range)
            guard Self.isRFC1918Private(candidate) else {
                continue
            }
            output.replaceCharacters(in: match.range, with: placeholder)
            count += 1
        }

        return TransformResult(output: output as String, changeCount: count)
    }

    private static func isRFC1918Private(_ candidate: String) -> Bool {
        let parts = candidate.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { Int($0) }
        guard
            parts.count == 4,
            octets.count == 4,
            octets.allSatisfy({ (0...255).contains($0) })
        else {
            return false
        }

        switch (octets[0], octets[1]) {
        case (10, _):
            return true
        case (172, 16...31):
            return true
        case (192, 168):
            return true
        default:
            return false
        }
    }
}
