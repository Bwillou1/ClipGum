import Foundation

public enum P2PError: LocalizedError, Equatable, Sendable {
    case malformedPacket
    case unsupportedVersion
    case invalidTransition
    case pairingNotReady
    case pairingCodeMismatch
    case authenticationFailed
    case replayDetected
    case payloadTooLarge
    case invalidUTF8
    case connectionClosed
    case invalidConfiguration

    public var errorDescription: String? {
        switch self {
        case .malformedPacket: return "The peer packet is malformed."
        case .unsupportedVersion: return "The peer protocol version is unsupported."
        case .invalidTransition: return "The peer message is not valid in the current session state."
        case .pairingNotReady: return "Pairing and mutual confirmation are required first."
        case .pairingCodeMismatch: return "The pairing code does not match this session."
        case .authenticationFailed: return "Peer authentication or message integrity failed."
        case .replayDetected: return "The peer message sequence is invalid or replayed."
        case .payloadTooLarge: return "The handoff exceeds the 2 MiB payload boundary."
        case .invalidUTF8: return "The handoff is not valid UTF-8 text."
        case .connectionClosed: return "The local peer connection is closed."
        case .invalidConfiguration: return "The local peer configuration is invalid."
        }
    }
}

struct P2PBinaryWriter {
    private(set) var data = Data()

    mutating func uint8(_ value: UInt8) { data.append(value) }

    mutating func uint16(_ value: UInt16) {
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    mutating func uint32(_ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    mutating func uint64(_ value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8((value >> UInt64(shift)) & 0xff))
        }
    }

    mutating func bytes(_ value: Data) { data.append(value) }

    mutating func uuid(_ value: UUID) {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: value.uuid) { bytes.append(contentsOf: $0) }
        data.append(contentsOf: bytes)
    }

    mutating func string(_ value: String, maximumBytes: Int) throws {
        let encoded = Data(value.utf8)
        guard encoded.count <= maximumBytes, encoded.count <= Int(UInt8.max) else {
            throw P2PError.invalidConfiguration
        }
        uint8(UInt8(encoded.count))
        bytes(encoded)
    }
}

struct P2PBinaryReader {
    private let storage: [UInt8]
    private var offset = 0

    init(_ data: Data) { storage = [UInt8](data) }

    var remaining: Int { storage.count - offset }

    mutating func uint8() throws -> UInt8 {
        guard remaining >= 1 else { throw P2PError.malformedPacket }
        defer { offset += 1 }
        return storage[offset]
    }

    mutating func uint16() throws -> UInt16 {
        let a = UInt16(try uint8())
        let b = UInt16(try uint8())
        return (a << 8) | b
    }

    mutating func uint32() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 { value = (value << 8) | UInt32(try uint8()) }
        return value
    }

    mutating func uint64() throws -> UInt64 {
        var value: UInt64 = 0
        for _ in 0..<8 { value = (value << 8) | UInt64(try uint8()) }
        return value
    }

    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, count <= remaining else { throw P2PError.malformedPacket }
        defer { offset += count }
        return Data(storage[offset..<(offset + count)])
    }

    mutating func uuid() throws -> UUID {
        let value = try bytes(16)
        let array = [UInt8](value)
        return UUID(uuid: (
            array[0], array[1], array[2], array[3],
            array[4], array[5], array[6], array[7],
            array[8], array[9], array[10], array[11],
            array[12], array[13], array[14], array[15]
        ))
    }

    mutating func string(maximumBytes: Int) throws -> String {
        let length = Int(try uint8())
        guard length <= maximumBytes else { throw P2PError.malformedPacket }
        let data = try bytes(length)
        guard let value = String(data: data, encoding: .utf8) else {
            throw P2PError.invalidUTF8
        }
        return value
    }

    func finish() throws {
        guard remaining == 0 else { throw P2PError.malformedPacket }
    }
}

public enum P2PFrameKind: UInt8, Sendable {
    case hello = 1
    case confirmation = 2
    case secure = 3
    case close = 4
}

public struct P2PFrame: Equatable, Sendable {
    public let kind: P2PFrameKind
    public let body: Data

    public init(kind: P2PFrameKind, body: Data = Data()) {
        self.kind = kind
        self.body = body
    }
}

public enum P2PFrameCodec {
    public static let maximumPayloadBytes = 2 * 1_024 * 1_024
    public static let maximumFrameBodyBytes = maximumPayloadBytes + 1_024
    public static let maximumBufferedBytes = maximumFrameBodyBytes + 5

    public static func encode(_ frame: P2PFrame) throws -> Data {
        guard frame.body.count <= maximumFrameBodyBytes else { throw P2PError.payloadTooLarge }
        var writer = P2PBinaryWriter()
        writer.uint32(UInt32(frame.body.count + 1))
        writer.uint8(frame.kind.rawValue)
        writer.bytes(frame.body)
        return writer.data
    }

    public static func decode(_ packet: Data) throws -> P2PFrame {
        guard packet.count >= 5, packet.count <= maximumBufferedBytes else {
            throw P2PError.malformedPacket
        }
        var reader = P2PBinaryReader(packet)
        let length = Int(try reader.uint32())
        guard length >= 1, length <= maximumFrameBodyBytes + 1,
              length == packet.count - 4 else {
            throw P2PError.malformedPacket
        }
        guard let kind = P2PFrameKind(rawValue: try reader.uint8()) else {
            throw P2PError.malformedPacket
        }
        let body = try reader.bytes(length - 1)
        try reader.finish()
        return P2PFrame(kind: kind, body: body)
    }
}

/// Incremental TCP framing. A length prefix is inspected before allocating a
/// frame, and malformed/oversized streams fail closed instead of accumulating.
public struct P2PFrameAccumulator {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ chunk: Data) throws -> [P2PFrame] {
        guard chunk.count <= P2PFrameCodec.maximumBufferedBytes,
              buffer.count + chunk.count <= P2PFrameCodec.maximumBufferedBytes else {
            throw P2PError.payloadTooLarge
        }
        buffer.append(chunk)
        var frames: [P2PFrame] = []
        while buffer.count >= 4 {
            let prefix = buffer.prefix(4)
            let length = prefix.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length >= 1, Int(length) <= P2PFrameCodec.maximumFrameBodyBytes + 1 else {
                throw P2PError.malformedPacket
            }
            let total = 4 + Int(length)
            guard buffer.count >= total else { break }
            let packet = buffer.prefix(total)
            frames.append(try P2PFrameCodec.decode(packet))
            buffer.removeSubrange(..<total)
        }
        return frames
    }

    public mutating func wipe() {
        buffer.withUnsafeMutableBytes { raw in
            if let address = raw.baseAddress { memset(address, 0, raw.count) }
        }
        buffer.removeAll(keepingCapacity: false)
    }
}

public struct P2PHello: Equatable, Sendable {
    public static let protocolVersion: UInt16 = 1
    public static let publicKeyBytes = 32
    public static let nonceBytes = 16

    public let sessionID: UUID
    public let publicKey: Data
    public let nonce: Data
    public let deviceName: String

    public init(sessionID: UUID = UUID(), publicKey: Data, nonce: Data, deviceName: String) throws {
        guard publicKey.count == Self.publicKeyBytes, nonce.count == Self.nonceBytes,
              publicKey.contains(where: { $0 != 0 }),
              deviceName.utf8.count <= 64 else {
            throw P2PError.invalidConfiguration
        }
        self.sessionID = sessionID
        self.publicKey = publicKey
        self.nonce = nonce
        self.deviceName = deviceName
    }

    func encode() throws -> Data {
        var writer = P2PBinaryWriter()
        writer.uint16(Self.protocolVersion)
        writer.uuid(sessionID)
        writer.bytes(publicKey)
        writer.bytes(nonce)
        try writer.string(deviceName, maximumBytes: 64)
        return writer.data
    }

    static func decode(_ data: Data) throws -> P2PHello {
        var reader = P2PBinaryReader(data)
        guard try reader.uint16() == protocolVersion else { throw P2PError.unsupportedVersion }
        let sessionID = try reader.uuid()
        let publicKey = try reader.bytes(publicKeyBytes)
        let nonce = try reader.bytes(nonceBytes)
        let name = try reader.string(maximumBytes: 64)
        try reader.finish()
        return try P2PHello(sessionID: sessionID, publicKey: publicKey, nonce: nonce, deviceName: name)
    }
}

struct P2PConfirmation: Equatable {
    let sessionID: UUID
    let transcriptDigest: Data

    func encode() -> Data {
        var writer = P2PBinaryWriter()
        writer.uuid(sessionID)
        writer.bytes(transcriptDigest)
        return writer.data
    }

    static func decode(_ data: Data) throws -> P2PConfirmation {
        var reader = P2PBinaryReader(data)
        let sessionID = try reader.uuid()
        let digest = try reader.bytes(32)
        try reader.finish()
        return P2PConfirmation(sessionID: sessionID, transcriptDigest: digest)
    }
}

struct P2PSecureEnvelope: Equatable {
    let sessionID: UUID
    let sequence: UInt64
    let ciphertext: Data

    func encode() -> Data {
        var writer = P2PBinaryWriter()
        writer.uuid(sessionID)
        writer.uint64(sequence)
        writer.bytes(ciphertext)
        return writer.data
    }

    static func decode(_ data: Data) throws -> P2PSecureEnvelope {
        var reader = P2PBinaryReader(data)
        let sessionID = try reader.uuid()
        let sequence = try reader.uint64()
        let remaining = reader.remaining
        let ciphertext = try reader.bytes(remaining)
        guard !ciphertext.isEmpty, ciphertext.count <= P2PFrameCodec.maximumPayloadBytes + 64 else {
            throw P2PError.malformedPacket
        }
        try reader.finish()
        return P2PSecureEnvelope(sessionID: sessionID, sequence: sequence, ciphertext: ciphertext)
    }
}
