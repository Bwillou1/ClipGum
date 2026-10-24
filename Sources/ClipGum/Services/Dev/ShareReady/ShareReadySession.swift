import Foundation

enum ShareReadyCategory: String, Hashable, Sendable {
    case privateIP
    case localhost
    case internalEndpoint
    case userDirectory
    case environmentValue
    case credential
}

struct ShareReadyResult: Equatable, Sendable {
    let output: String
    let replacementCount: Int
    let replacementsByCategory: [ShareReadyCategory: Int]
    let mappingCount: Int
}

/// Volatile, bidirectional identifier mapping for one app session. No bookmark,
/// UserDefaults, file, logging, or model API is used by this type.
final class ShareReadySession: @unchecked Sendable {
    private struct ForwardKey: Hashable {
        let category: ShareReadyCategory
        let realValue: String
    }

    private let lock = NSLock()
    private var forward: [ForwardKey: String] = [:]
    private var reverse: [String: String] = [:]
    private var nextOrdinals: [ShareReadyCategory: Int] = [:]

    private static let awsAccessKey = try! NSRegularExpression(
        pattern: #"\b(?:A3T[A-Z0-9]|AKIA|ASIA|ABIA|ACCA)[A-Z2-7]{16}\b"#
    )
    private static let bearerToken = try! NSRegularExpression(
        pattern: #"\bBearer[ \t]+([-A-Za-z0-9._~+/=%]{8,})"#,
        options: [.caseInsensitive]
    )
    private static let basicAuthentication = try! NSRegularExpression(
        pattern: #"(?i)\b(https?://)([^/\s@]+)@"#
    )
    private static let privateKey = try! NSRegularExpression(
        pattern: #"(?s)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----.*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#
    )
    private static let environmentAssignment = try! NSRegularExpression(
        pattern: #"(?i)\b(?:[A-Z0-9_]*(?:API[_-]?KEY|ACCESS[_-]?TOKEN|REFRESH[_-]?TOKEN|AUTH[_-]?TOKEN|CLIENT[_-]?SECRET|SECRET(?:[_-]?(?:ACCESS[_-]?)?KEY)?|TOKEN|PASSW(?:OR)?D|CREDENTIALS?|PRIVATE[_-]?KEY|DATABASE_URL))\b[\"']?\s*[:=]\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s;,}\]]+))"#
    )
    private static let userDirectory = try! NSRegularExpression(
        pattern: #"\/Users\/[A-Za-z0-9._-]+"#
    )
    private static let ipv4Candidate = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_.])(?:\d{1,3}\.){3}\d{1,3}(?![A-Za-z0-9_.])"#
    )
    private static let localhost = try! NSRegularExpression(
        pattern: #"(?i)(?<![A-Za-z0-9_-])localhost(?![A-Za-z0-9_.-])"#
    )
    private static let localhostIPv6 = try! NSRegularExpression(
        pattern: #"(?<![0-9A-Fa-f:])::1(?![0-9A-Fa-f:])"#
    )
    private static let internalEndpoint = try! NSRegularExpression(
        pattern: #"(?i)(?<![A-Za-z0-9_-])(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+(?:(?:internal|intranet|intra|corp|local|lan|home\.arpa)(?![A-Za-z0-9_.-])|(?:internal|intranet|intra|corp)(?:\.[a-z]{2,})+(?![A-Za-z0-9_.-]))"#
    )

    var mappingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return reverse.count
    }

    func anonymize(_ input: String) -> ShareReadyResult {
        lock.lock()
        defer { lock.unlock() }

        var output = input
        var counts: [ShareReadyCategory: Int] = [:]
        apply(Self.privateKey, category: .credential, to: &output, counts: &counts)
        apply(Self.environmentAssignment, category: .environmentValue, groups: [1, 2, 3], to: &output, counts: &counts)
        apply(Self.basicAuthentication, category: .credential, groups: [2], to: &output, counts: &counts)
        apply(Self.awsAccessKey, category: .credential, to: &output, counts: &counts)
        apply(Self.bearerToken, category: .credential, groups: [1], to: &output, counts: &counts)
        apply(Self.userDirectory, category: .userDirectory, to: &output, counts: &counts)
        apply(Self.ipv4Candidate, category: .privateIP, to: &output, counts: &counts) {
            Self.isRFC1918Private($0)
        }
        apply(Self.localhostIPv6, category: .localhost, to: &output, counts: &counts)
        apply(Self.localhost, category: .localhost, to: &output, counts: &counts)
        apply(Self.internalEndpoint, category: .internalEndpoint, to: &output, counts: &counts)

        return ShareReadyResult(
            output: output,
            replacementCount: counts.values.reduce(0, +),
            replacementsByCategory: counts,
            mappingCount: reverse.count
        )
    }

    func restore(_ input: String) -> ShareReadyResult {
        lock.lock()
        defer { lock.unlock() }

        var output = input
        var replacements = 0
        // Longest-first avoids a short synthetic value consuming a longer one.
        for synthetic in reverse.keys.sorted(by: { $0.count > $1.count }) {
            guard let real = reverse[synthetic] else { continue }
            let components = output.components(separatedBy: synthetic)
            guard components.count > 1 else { continue }
            replacements += components.count - 1
            output = components.joined(separator: real)
        }
        return ShareReadyResult(
            output: output,
            replacementCount: replacements,
            replacementsByCategory: [:],
            mappingCount: reverse.count
        )
    }

    func clear() {
        lock.lock()
        forward.removeAll()
        reverse.removeAll()
        nextOrdinals.removeAll()
        lock.unlock()
    }

    func syntheticValue(for realValue: String, category: ShareReadyCategory) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return forward[ForwardKey(category: category, realValue: realValue)]
    }

    func originalValue(for syntheticValue: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return reverse[syntheticValue]
    }

    private func apply(
        _ expression: NSRegularExpression,
        category: ShareReadyCategory,
        groups: [Int] = [0],
        to output: inout String,
        counts: inout [ShareReadyCategory: Int],
        shouldReplace: (String) -> Bool = { _ in true }
    ) {
        let source = output
        let matches = expression.matches(in: source, range: NSRange(source.startIndex..., in: source))
        guard !matches.isEmpty else { return }
        var rebuilt = ""
        var cursor = source.startIndex
        var changed = 0

        for match in matches {
            guard let capture = groups.lazy.compactMap({ group -> Range<String.Index>? in
                let range = match.range(at: group)
                guard range.location != NSNotFound, range.length > 0 else { return nil }
                return Range(range, in: source)
            }).first else {
                continue
            }
            let real = String(source[capture])
            guard shouldReplace(real) else { continue }
            rebuilt += String(source[cursor..<capture.lowerBound])
            rebuilt += mappedValue(for: real, category: category, forbiddenIn: source)
            cursor = capture.upperBound
            changed += 1
        }
        guard changed > 0 else { return }
        rebuilt += String(source[cursor...])
        output = rebuilt
        counts[category, default: 0] += changed
    }

    private func mappedValue(
        for realValue: String,
        category: ShareReadyCategory,
        forbiddenIn source: String
    ) -> String {
        let key = ForwardKey(category: category, realValue: realValue)
        if let existing = forward[key] { return existing }

        var candidate = ""
        switch category {
        case .privateIP, .environmentValue, .credential:
            var ordinal = nextOrdinals[category, default: 1]
            repeat {
                switch category {
                case .privateIP: candidate = "host-\(ordinal).example.test"
                case .environmentValue: candidate = "[ENV_VALUE_\(ordinal)]"
                case .credential: candidate = "[CREDENTIAL_\(ordinal)]"
                default: break
                }
                ordinal += 1
            } while reverse[candidate] != nil || source.contains(candidate)
            nextOrdinals[category] = ordinal
        case .localhost, .internalEndpoint, .userDirectory:
            var suffix = 1
            let base: String
            switch category {
            case .localhost:
                base = "localhost"
            case .internalEndpoint:
                let first = realValue.split(separator: ".").first.map(String.init) ?? "service"
                base = first.lowercased().map { character in
                    character.isLetter || character.isNumber || character == "-" ? character : "-"
                }.reduce(into: "") { $0.append($1) }
            case .userDirectory:
                base = "[USER]"
            default:
                base = "service"
            }
            repeat {
                switch category {
                case .localhost, .internalEndpoint:
                    let host = suffix == 1 ? base : "\(base)-\(suffix)"
                    candidate = "\(host).example.test"
                case .userDirectory:
                    candidate = suffix == 1 ? "/Users/[USER]" : "/Users/[USER_\(suffix)]"
                default:
                    break
                }
                suffix += 1
            } while reverse[candidate] != nil || source.contains(candidate)
        }

        forward[key] = candidate
        reverse[candidate] = realValue
        return candidate
    }

    private static func isRFC1918Private(_ candidate: String) -> Bool {
        let parts = candidate.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { Int($0) }
        guard parts.count == 4, octets.count == 4,
            octets.allSatisfy({ (0...255).contains($0) })
        else {
            return false
        }
        switch (octets[0], octets[1]) {
        case (10, _): return true
        case (172, 16...31): return true
        case (192, 168): return true
        default: return false
        }
    }
}
