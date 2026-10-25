import CryptoKit
import Foundation

public struct RulePack: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var rules: [CustomRule]
    public var checksum: String

    public init(schemaVersion: Int = 1, rules: [CustomRule], checksum: String) {
        self.schemaVersion = schemaVersion
        self.rules = rules
        self.checksum = checksum
    }
}

private struct RulePackPayload: Codable {
    var schemaVersion: Int
    var rules: [CustomRule]
}

public enum RulePackCodec {
    public static let maximumPackBytes = 2 * 1_024 * 1_024
    public static let maximumRules = 100

    public static func encode(rules: [CustomRule]) throws -> Data {
        try validate(rules: rules)
        let payload = RulePackPayload(schemaVersion: 1, rules: rules)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let payloadData = try encoder.encode(payload)
        let checksum = digest(payloadData)
        let pack = RulePack(rules: rules, checksum: checksum)
        return try encoder.encode(pack)
    }

    public static func decode(_ data: Data) throws -> [CustomRule] {
        guard data.count <= maximumPackBytes else { throw CustomRuleError.invalidRulePack }
        let decoder = JSONDecoder()
        let pack: RulePack
        do {
            pack = try decoder.decode(RulePack.self, from: data)
        } catch {
            throw CustomRuleError.invalidRulePack
        }
        guard pack.schemaVersion == 1, pack.checksum.count == 64 else {
            throw CustomRuleError.invalidRulePack
        }
        let payload = RulePackPayload(schemaVersion: pack.schemaVersion, rules: pack.rules)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let payloadData = try encoder.encode(payload)
        guard digest(payloadData).caseInsensitiveCompare(pack.checksum) == .orderedSame else {
            throw CustomRuleError.checksumMismatch
        }
        try validate(rules: pack.rules)
        return pack.rules
    }

    public static func validate(rules: [CustomRule]) throws {
        guard rules.count <= maximumRules else { throw CustomRuleError.tooManyRules }
        var ids: Set<UUID> = []
        for rule in rules {
            guard !rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  rule.name.utf8.count <= 128,
                  !ids.contains(rule.id) else {
                throw CustomRuleError.invalidRulePack
            }
            ids.insert(rule.id)
            switch rule.kind {
            case .regex:
                guard rule.source.utf8.count <= 16 * 1_024 else {
                    throw CustomRuleError.sourceTooLarge
                }
                do {
                    _ = try NSRegularExpression(pattern: rule.source)
                } catch {
                    throw CustomRuleError.invalidExpression
                }
            case .script:
                guard rule.source.utf8.count <= JavaScriptPluginEngine.maximumSourceBytes else {
                    throw CustomRuleError.sourceTooLarge
                }
            }
        }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public final class RuleRepository {
    public let storeURL: URL

    public init(storeURL: URL? = nil) {
        if let storeURL {
            self.storeURL = storeURL
        } else {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.storeURL = root.appendingPathComponent("ClipGum/CustomRules.json", isDirectory: false)
        }
    }

    public func load() throws -> [CustomRule] {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return [] }
        let data = try Data(contentsOf: storeURL, options: [.mappedIfSafe])
        return try RulePackCodec.decode(data)
    }

    public func save(rules: [CustomRule]) throws {
        let data = try RulePackCodec.encode(rules: rules)
        let directory = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: storeURL, options: [.atomic])
    }

    public func importPack(from url: URL) throws -> [CustomRule] {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return try RulePackCodec.decode(data)
    }

    public func exportPack(rules: [CustomRule], to url: URL) throws {
        let data = try RulePackCodec.encode(rules: rules)
        try data.write(to: url, options: [.atomic])
    }
}
