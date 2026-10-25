import Argon2
import CryptoKit
import Foundation
import Security

public enum LocalBackupError: LocalizedError, Equatable, Sendable {
    case invalidPassword
    case invalidArchive
    case unsupportedArchive
    case authenticationFailed
    case payloadTooLarge
    case unsafeConfiguration
    case invalidParameters

    public var errorDescription: String? {
        switch self {
        case .invalidPassword: return "Enter a password between 8 and 1,024 UTF-8 bytes."
        case .invalidArchive: return "The ClipGum backup is malformed."
        case .unsupportedArchive: return "The ClipGum backup version or cryptography is unsupported."
        case .authenticationFailed: return "The password is incorrect or the backup was modified."
        case .payloadTooLarge: return "The backup exceeds the local configuration size boundary."
        case .unsafeConfiguration: return "The backup contains fields outside the portable configuration schema."
        case .invalidParameters: return "The backup security parameters are outside safe limits."
        }
    }
}

/// Deliberately typed allow-list for portable preferences. Clipboard text,
/// pasteboard flavors, histories, Share-Ready mappings, and session keys have
/// no representation here and therefore cannot be exported accidentally.
public struct PortableSettings: Codable, Equatable, Sendable {
    public var locale: String?
    public var modelIdentifier: String?
    public var temperature: Double
    public var modelOffloadSeconds: Int
    public var maximumOutputTokens: Int
    public var telemetryEnabled: Bool
    public var mobileKeyboardEnabled: Bool

    public init(
        locale: String? = nil,
        modelIdentifier: String? = nil,
        temperature: Double = 0.2,
        modelOffloadSeconds: Int = 900,
        maximumOutputTokens: Int = 512,
        telemetryEnabled: Bool = false,
        mobileKeyboardEnabled: Bool = false
    ) {
        self.locale = locale
        self.modelIdentifier = modelIdentifier
        self.temperature = temperature
        self.modelOffloadSeconds = modelOffloadSeconds
        self.maximumOutputTokens = maximumOutputTokens
        self.telemetryEnabled = telemetryEnabled
        self.mobileKeyboardEnabled = mobileKeyboardEnabled
    }

    func validate() throws {
        guard (locale?.utf8.count ?? 0) <= 64,
              (modelIdentifier?.utf8.count ?? 0) <= 256,
              temperature.isFinite, (0.1...0.3).contains(temperature),
              (0...86_400).contains(modelOffloadSeconds),
              (1...4_096).contains(maximumOutputTokens) else {
            throw LocalBackupError.unsafeConfiguration
        }
    }
}

public struct ClipGumBackupPayload: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var rules: [CustomRule]
    public var settings: PortableSettings

    public init(rules: [CustomRule], settings: PortableSettings = PortableSettings()) {
        schemaVersion = 1
        self.rules = rules
        self.settings = settings
    }
}

public struct BackupAuditReport: Equatable, Sendable {
    public let ruleCount: Int
    public let includesClipboardHistory: Bool
    public let includesSessionMappings: Bool

    public init(ruleCount: Int) {
        self.ruleCount = ruleCount
        includesClipboardHistory = false
        includesSessionMappings = false
    }
}

/// Password-protected, local-only configuration archives. This type performs
/// no file I/O; an explicit caller chooses the security-scoped destination.
public enum LocalBackupArchive {
    public static let fileExtension = "clipgum"
    public static let maximumArchiveBytes = 4 * 1_024 * 1_024
    public static let maximumPlaintextBytes = 2 * 1_024 * 1_024
    public static let defaultParameters = Argon2Params(
        variant: .id,
        timeCost: 3,
        memoryCostKilobytes: 65_536,
        parallelism: 4,
        outputLength: 32
    )

    private static let magic = Data([0x43, 0x4c, 0x50, 0x47]) // CLPG
    private static let fixedHeaderBytes = 24
    private static let associatedData = Data("ClipGum/local-backup/v1".utf8)

    public static func export(
        payload: ClipGumBackupPayload,
        password: String,
        parameters: Argon2Params = LocalBackupArchive.defaultParameters
    ) throws -> Data {
        try validatePassword(password)
        try validateParameters(parameters)
        try validatePayload(payload)
        var plaintext = try encodeAndAudit(payload)
        defer { wipe(&plaintext) }
        guard plaintext.count <= maximumPlaintextBytes else { throw LocalBackupError.payloadTooLarge }

        var passwordData = Data(password.utf8)
        defer { wipe(&passwordData) }
        let salt = try randomBytes(16)
        let nonceData = try randomBytes(12)
        var keyData = try Argon2.deriveKey(
            password: passwordData,
            salt: salt,
            associatedData: associatedData,
            params: parameters
        )
        defer { wipe(&keyData) }
        let key = SymmetricKey(data: keyData)
        let nonce = try AES.GCM.Nonce(data: nonceData)

        var writer = BackupWriter()
        writer.bytes(magic)
        writer.uint8(1) // envelope version
        writer.uint8(1) // Argon2id
        writer.uint8(1) // AES-256-GCM
        writer.uint8(0) // reserved flags
        writer.uint32(parameters.timeCost)
        writer.uint32(parameters.memoryCostKilobytes)
        writer.uint32(parameters.parallelism)
        writer.uint16(UInt16(salt.count))
        writer.uint16(UInt16(nonceData.count))
        writer.bytes(salt)
        writer.bytes(nonceData)
        let header = writer.data
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: header)
        var archive = header
        archive.append(box.ciphertext)
        archive.append(box.tag)
        guard archive.count <= maximumArchiveBytes else { throw LocalBackupError.payloadTooLarge }
        return archive
    }

    public static func `import`(_ archive: Data, password: String) throws -> ClipGumBackupPayload {
        try validatePassword(password)
        guard archive.count >= fixedHeaderBytes + 16 + 12 + 16,
              archive.count <= maximumArchiveBytes else {
            throw LocalBackupError.invalidArchive
        }
        var reader = BackupReader(archive)
        guard try reader.bytes(4) == magic else { throw LocalBackupError.invalidArchive }
        let version = try reader.uint8()
        let kdf = try reader.uint8()
        let cipher = try reader.uint8()
        let flags = try reader.uint8()
        guard version == 1, kdf == 1, cipher == 1, flags == 0 else {
            throw LocalBackupError.unsupportedArchive
        }
        let timeCost = try reader.uint32()
        let memory = try reader.uint32()
        let lanes = try reader.uint32()
        let saltLength = Int(try reader.uint16())
        let nonceLength = Int(try reader.uint16())
        guard saltLength == 16, nonceLength == 12 else { throw LocalBackupError.invalidParameters }
        let parameters = Argon2Params(
            variant: .id,
            timeCost: timeCost,
            memoryCostKilobytes: memory,
            parallelism: lanes,
            outputLength: 32
        )
        try validateParameters(parameters)
        let salt = try reader.bytes(saltLength)
        let nonceData = try reader.bytes(nonceLength)
        let headerLength = fixedHeaderBytes + saltLength + nonceLength
        guard archive.count > headerLength + 16 else { throw LocalBackupError.invalidArchive }
        let ciphertextLength = archive.count - headerLength - 16
        guard ciphertextLength <= maximumPlaintextBytes else { throw LocalBackupError.payloadTooLarge }
        let ciphertext = try reader.bytes(ciphertextLength)
        let tag = try reader.bytes(16)
        try reader.finish()
        let header = archive.prefix(headerLength)

        var passwordData = Data(password.utf8)
        defer { wipe(&passwordData) }
        var keyData: Data
        do {
            keyData = try Argon2.deriveKey(
                password: passwordData,
                salt: salt,
                associatedData: associatedData,
                params: parameters
            )
        } catch {
            throw LocalBackupError.invalidParameters
        }
        defer { wipe(&keyData) }
        let key = SymmetricKey(data: keyData)
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            var plaintext = try AES.GCM.open(box, using: key, authenticating: Data(header))
            defer { wipe(&plaintext) }
            guard plaintext.count <= maximumPlaintextBytes else { throw LocalBackupError.payloadTooLarge }
            try audit(plaintext)
            let payload = try JSONDecoder().decode(ClipGumBackupPayload.self, from: plaintext)
            try validatePayload(payload)
            return payload
        } catch let error as LocalBackupError {
            throw error
        } catch {
            throw LocalBackupError.authenticationFailed
        }
    }

    public static func auditReport(for payload: ClipGumBackupPayload) throws -> BackupAuditReport {
        try validatePayload(payload)
        _ = try encodeAndAudit(payload)
        return BackupAuditReport(ruleCount: payload.rules.count)
    }

    public static func audit(_ plaintext: Data) throws {
        guard plaintext.count <= maximumPlaintextBytes,
              let object = try? JSONSerialization.jsonObject(with: plaintext),
              let dictionary = object as? [String: Any] else {
            throw LocalBackupError.invalidArchive
        }
        let topLevel: Set<String> = ["schemaVersion", "rules", "settings"]
        guard Set(dictionary.keys) == topLevel,
              dictionary["schemaVersion"] as? Int == 1,
              let rules = dictionary["rules"] as? [[String: Any]],
              let settings = dictionary["settings"] as? [String: Any] else {
            throw LocalBackupError.unsafeConfiguration
        }
        let ruleKeys: Set<String> = ["id", "name", "kind", "source", "replacement", "isEnabled"]
        for rule in rules where Set(rule.keys) != ruleKeys {
            throw LocalBackupError.unsafeConfiguration
        }
        let settingsKeys: Set<String> = [
            "locale", "modelIdentifier", "temperature", "modelOffloadSeconds", "maximumOutputTokens",
            "telemetryEnabled", "mobileKeyboardEnabled"
        ]
        guard Set(settings.keys).isSubset(of: settingsKeys) else {
            throw LocalBackupError.unsafeConfiguration
        }
        try rejectForbiddenKeys(dictionary)
    }

    private static func validatePayload(_ payload: ClipGumBackupPayload) throws {
        guard payload.schemaVersion == 1 else { throw LocalBackupError.unsupportedArchive }
        try RulePackCodec.validate(rules: payload.rules)
        try payload.settings.validate()
        let data = try JSONEncoder.sorted.encode(payload)
        guard data.count <= maximumPlaintextBytes else { throw LocalBackupError.payloadTooLarge }
    }

    private static func encodeAndAudit(_ payload: ClipGumBackupPayload) throws -> Data {
        let data = try JSONEncoder.sorted.encode(payload)
        try audit(data)
        return data
    }

    private static func rejectForbiddenKeys(_ value: Any) throws {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                let normalized = key.lowercased()
                let forbidden = [
                    "clipboard", "pasteboard", "history", "sessionmapping", "session_key",
                    "privatekey", "sharedsecret", "originaltext", "cleanedtext"
                ]
                guard !forbidden.contains(where: { normalized.contains($0) }) else {
                    throw LocalBackupError.unsafeConfiguration
                }
                try rejectForbiddenKeys(child)
            }
        } else if let array = value as? [Any] {
            for child in array { try rejectForbiddenKeys(child) }
        }
    }

    private static func validatePassword(_ password: String) throws {
        let count = password.utf8.count
        guard (8...1_024).contains(count) else { throw LocalBackupError.invalidPassword }
    }

    private static func validateParameters(_ parameters: Argon2Params) throws {
        guard parameters.variant == .id, parameters.version == 0x13,
              parameters.outputLength == 32,
              (1...8).contains(parameters.timeCost),
              (1...8).contains(parameters.parallelism),
              parameters.memoryCostKilobytes >= 8 * parameters.parallelism,
              parameters.memoryCostKilobytes <= 131_072 else {
            throw LocalBackupError.invalidParameters
        }
    }

    private static func randomBytes(_ count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { raw in
            SecRandomCopyBytes(kSecRandomDefault, count, raw.baseAddress)
        }
        guard status == errSecSuccess else { throw LocalBackupError.invalidParameters }
        return data
    }

    private static func wipe(_ data: inout Data) {
        data.withUnsafeMutableBytes { raw in
            if let address = raw.baseAddress { memset(address, 0, raw.count) }
        }
        data.removeAll(keepingCapacity: false)
    }
}

private struct BackupWriter {
    private(set) var data = Data()
    mutating func uint8(_ value: UInt8) { data.append(value) }
    mutating func uint16(_ value: UInt16) {
        data.append(UInt8(value >> 8)); data.append(UInt8(value & 0xff))
    }
    mutating func uint32(_ value: UInt32) {
        for shift in stride(from: 24, through: 0, by: -8) {
            data.append(UInt8((value >> UInt32(shift)) & 0xff))
        }
    }
    mutating func bytes(_ value: Data) { data.append(value) }
}

private struct BackupReader {
    private let storage: [UInt8]
    private var offset = 0
    init(_ data: Data) { storage = [UInt8](data) }
    var remaining: Int { storage.count - offset }
    mutating func uint8() throws -> UInt8 {
        guard remaining >= 1 else { throw LocalBackupError.invalidArchive }
        defer { offset += 1 }; return storage[offset]
    }
    mutating func uint16() throws -> UInt16 {
        let high = UInt16(try uint8()); let low = UInt16(try uint8()); return (high << 8) | low
    }
    mutating func uint32() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 { value = (value << 8) | UInt32(try uint8()) }
        return value
    }
    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, count <= remaining else { throw LocalBackupError.invalidArchive }
        defer { offset += count }; return Data(storage[offset..<(offset + count)])
    }
    func finish() throws { guard remaining == 0 else { throw LocalBackupError.invalidArchive } }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
