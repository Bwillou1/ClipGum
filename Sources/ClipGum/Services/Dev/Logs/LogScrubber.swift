import Foundation

struct LogScrubResult: Equatable, Sendable {
    let output: String
    let removedStackFrames: Int
    let removedTimestamps: Int
    let redactedSecrets: Int
}

/// Deterministic terminal-log cleanup. It performs text transforms only and
/// never invokes a shell, logging service, or inference engine.
struct LogScrubber {
    private let secretRedactor = SecretRedactor(
        placeholder: RuleCleaningService.redactionPlaceholder
    )

    private static let ansiCSI = try! NSRegularExpression(
        pattern: "\u{1B}\\[[0-?]*[ -/]*[@-~]"
    )
    private static let ansiOSC = try! NSRegularExpression(
        pattern: "\u{1B}\\][^\u{7}]*(?:\u{7}|\u{1B}\\\\)"
    )
    private static let leadingTimestamp = try! NSRegularExpression(
        pattern: #"(?i)^\s*(?:\[(?:\d{4}-\d{2}-\d{2}[T ])?\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?\]|\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?|\d{2}:\d{2}:\d{2}(?:[.,]\d+)?|[A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+"#
    )
    private static let stackFrame = try! NSRegularExpression(
        pattern: #"(?i)^\s*(?:at\s+(?:.*\(.*\)|\S+:\d+(?::\d+)?)|File\s+\".+\",\s+line\s+\d+.*|#\d+\s+.*|\d+\s+\S+\s+0x[0-9a-f]+\s+.*|\.\.\.\s*\d+\s+more\s*)$"#
    )
    private static let ipv4Candidate = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_.])(?:\d{1,3}\.){3}\d{1,3}(?![A-Za-z0-9_.])"#
    )
    private static let localIPv6 = try! NSRegularExpression(
        pattern: #"(?i)(?<![0-9a-f:])(?:::1|(?:f[cd][0-9a-f]{2}|fe[89ab][0-9a-f]):[0-9a-f:]+)(?![0-9a-f:])"#
    )

    func scrub(_ input: String) -> LogScrubResult {
        var ansiFree = Self.remove(Self.ansiOSC, from: input)
        ansiFree = Self.remove(Self.ansiCSI, from: ansiFree)

        var removedFrames = 0
        var removedTimestamps = 0
        let normalizedLines = ansiFree
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalizedLines.components(separatedBy: "\n")
        let kept = lines.filter { line in
            let range = NSRange(line.startIndex..., in: line)
            if Self.stackFrame.firstMatch(in: line, range: range) != nil {
                removedFrames += 1
                return false
            }
            return true
        }.map { line in
            guard let match = Self.leadingTimestamp.firstMatch(
                in: line,
                range: NSRange(line.startIndex..., in: line)
            ), let range = Range(match.range, in: line) else {
                return line
            }
            removedTimestamps += 1
            return String(line[range.upperBound...])
        }

        let redaction = secretRedactor.redactSecrets(in: kept.joined(separator: "\n"))
        let localAddresses = redactLocalAddresses(in: redaction.output)
        let loopback = Self.localIPv6.stringByReplacingMatches(
            in: localAddresses.output,
            range: NSRange(localAddresses.output.startIndex..., in: localAddresses.output),
            withTemplate: RuleCleaningService.redactionPlaceholder
        )
        let loopbackCount = Self.localIPv6.numberOfMatches(
            in: localAddresses.output,
            range: NSRange(localAddresses.output.startIndex..., in: localAddresses.output)
        )
        return LogScrubResult(
            output: loopback,
            removedStackFrames: removedFrames,
            removedTimestamps: removedTimestamps,
            redactedSecrets: redaction.changeCount + localAddresses.changeCount + loopbackCount
        )
    }

    private func redactLocalAddresses(in input: String) -> TransformResult {
        let matches = Self.ipv4Candidate.matches(
            in: input,
            range: NSRange(input.startIndex..., in: input)
        )
        let output = NSMutableString(string: input)
        var count = 0
        for match in matches.reversed() {
            let candidate = output.substring(with: match.range)
            let octets = candidate.split(separator: ".").compactMap { Int($0) }
            guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }),
                octets[0] == 127 || octets[0] == 0
                    || (octets[0] == 169 && octets[1] == 254)
            else {
                continue
            }
            output.replaceCharacters(in: match.range, with: RuleCleaningService.redactionPlaceholder)
            count += 1
        }
        return TransformResult(output: output as String, changeCount: count)
    }

    private static func remove(_ expression: NSRegularExpression, from input: String) -> String {
        expression.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: ""
        )
    }
}
