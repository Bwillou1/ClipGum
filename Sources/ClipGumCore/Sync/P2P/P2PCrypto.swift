import CryptoKit
import Foundation
import Security

/// Ephemeral X25519 pairing with a six-digit short-authentication-string (SAS).
/// The code is derived from both ephemeral public keys and nonces. Both users
/// must compare and explicitly confirm it before a secure channel can exist.
public struct P2PPairingSession {
    public let isInitiator: Bool
    public let localHello: P2PHello
    private let privateKey: Curve25519.KeyAgreement.PrivateKey
    private var remoteHello: P2PHello?

    public init(deviceName: String, isInitiator: Bool) throws {
        self.isInitiator = isInitiator
        let key = Curve25519.KeyAgreement.PrivateKey()
        privateKey = key
        var nonce = Data(count: P2PHello.nonceBytes)
        let status = nonce.withUnsafeMutableBytes { raw -> OSStatus in
            guard let address = raw.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, P2PHello.nonceBytes, address)
        }
        guard status == errSecSuccess else { throw P2PError.invalidConfiguration }
        localHello = try P2PHello(
            publicKey: key.publicKey.rawRepresentation,
            nonce: nonce,
            deviceName: deviceName
        )
    }

    public var pairingCode: String? {
        guard let transcript = transcriptDigest else { return nil }
        let value = transcript.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } % 1_000_000
        let digits = String(value)
        return String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }

    public var remoteDeviceName: String? { remoteHello?.deviceName }

    public var sessionID: UUID? {
        guard let remoteHello else { return nil }
        return isInitiator ? localHello.sessionID : remoteHello.sessionID
    }

    public mutating func receiveHello(_ hello: P2PHello) throws -> String {
        guard remoteHello == nil, hello.publicKey != localHello.publicKey,
              hello.sessionID != localHello.sessionID else {
            throw P2PError.invalidTransition
        }
        remoteHello = hello
        guard let pairingCode else { throw P2PError.authenticationFailed }
        return pairingCode
    }

    public func confirmation() throws -> P2PFrame {
        guard let sessionID, let transcriptDigest else { throw P2PError.pairingNotReady }
        return P2PFrame(
            kind: .confirmation,
            body: P2PConfirmation(sessionID: sessionID, transcriptDigest: transcriptDigest).encode()
        )
    }

    public func validateConfirmation(_ frame: P2PFrame) throws {
        guard frame.kind == .confirmation, let sessionID, let transcriptDigest else {
            throw P2PError.pairingNotReady
        }
        let confirmation = try P2PConfirmation.decode(frame.body)
        guard confirmation.sessionID == sessionID,
              confirmation.transcriptDigest == transcriptDigest else {
            throw P2PError.authenticationFailed
        }
    }

    public func makeSecureChannel() throws -> P2PSecureChannel {
        guard let remoteHello, let sessionID, let transcriptDigest else {
            throw P2PError.pairingNotReady
        }
        let remoteKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: remoteHello.publicKey)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: remoteKey)
        let sharedData = shared.withUnsafeBytes { Data($0) }
        let sendInfo = isInitiator ? "initiator-to-responder" : "responder-to-initiator"
        let receiveInfo = isInitiator ? "responder-to-initiator" : "initiator-to-responder"
        let sendKey = Self.deriveKey(shared: sharedData, transcript: transcriptDigest, info: sendInfo)
        let receiveKey = Self.deriveKey(shared: sharedData, transcript: transcriptDigest, info: receiveInfo)
        return P2PSecureChannel(
            sessionID: sessionID,
            sendKey: sendKey,
            receiveKey: receiveKey,
            sendDirection: isInitiator ? 0 : 1,
            receiveDirection: isInitiator ? 1 : 0
        )
    }

    private var transcriptDigest: Data? {
        guard let remoteHello else { return nil }
        do {
            let local = try localHello.encode()
            let remote = try remoteHello.encode()
            var transcript = Data("ClipGum/P2P/SAS/v1".utf8)
            transcript.append(isInitiator ? local : remote)
            transcript.append(isInitiator ? remote : local)
            return Data(SHA256.hash(data: transcript))
        } catch {
            return nil
        }
    }

    private static func deriveKey(shared: Data, transcript: Data, info: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: shared),
            salt: transcript,
            info: Data(info.utf8),
            outputByteCount: 32
        )
    }
}

/// Direction-separated ChaCha20-Poly1305 channel. TCP order plus an exact
/// expected sequence rejects replay, reordering, and cross-session envelopes.
public struct P2PSecureChannel {
    public let sessionID: UUID
    private let sendKey: SymmetricKey
    private let receiveKey: SymmetricKey
    private let sendDirection: UInt8
    private let receiveDirection: UInt8

    init(
        sessionID: UUID,
        sendKey: SymmetricKey,
        receiveKey: SymmetricKey,
        sendDirection: UInt8,
        receiveDirection: UInt8
    ) {
        self.sessionID = sessionID
        self.sendKey = sendKey
        self.receiveKey = receiveKey
        self.sendDirection = sendDirection
        self.receiveDirection = receiveDirection
    }

    public func seal(_ plaintext: Data, sequence: UInt64) throws -> P2PFrame {
        // The text boundary is 2 MiB; the framed transfer also carries its
        // kind, UUID, and length before the AEAD tag is appended.
        guard plaintext.count <= P2PFrameCodec.maximumPayloadBytes + 64 else {
            throw P2PError.payloadTooLarge
        }
        let nonce = try Self.nonce(sessionID: sessionID, direction: sendDirection, sequence: sequence)
        let associated = Self.associatedData(sessionID: sessionID, direction: sendDirection, sequence: sequence)
        let box = try ChaChaPoly.seal(plaintext, using: sendKey, nonce: nonce, authenticating: associated)
        var ciphertext = box.ciphertext
        ciphertext.append(box.tag)
        return P2PFrame(
            kind: .secure,
            body: P2PSecureEnvelope(sessionID: sessionID, sequence: sequence, ciphertext: ciphertext).encode()
        )
    }

    public func open(_ frame: P2PFrame, expectedSequence: UInt64) throws -> Data {
        guard frame.kind == .secure else { throw P2PError.invalidTransition }
        let envelope = try P2PSecureEnvelope.decode(frame.body)
        guard envelope.sessionID == sessionID else { throw P2PError.authenticationFailed }
        guard envelope.sequence == expectedSequence else { throw P2PError.replayDetected }
        guard envelope.ciphertext.count > 16 else { throw P2PError.malformedPacket }
        let split = envelope.ciphertext.count - 16
        let ciphertext = envelope.ciphertext.prefix(split)
        let tag = envelope.ciphertext.suffix(16)
        let nonce = try Self.nonce(sessionID: sessionID, direction: receiveDirection, sequence: expectedSequence)
        let associated = Self.associatedData(sessionID: sessionID, direction: receiveDirection, sequence: expectedSequence)
        do {
            let box = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            return try ChaChaPoly.open(box, using: receiveKey, authenticating: associated)
        } catch {
            throw P2PError.authenticationFailed
        }
    }

    private static func associatedData(sessionID: UUID, direction: UInt8, sequence: UInt64) -> Data {
        var writer = P2PBinaryWriter()
        writer.uuid(sessionID)
        writer.uint8(direction)
        writer.uint64(sequence)
        return writer.data
    }

    private static func nonce(sessionID: UUID, direction: UInt8, sequence: UInt64) throws -> ChaChaPoly.Nonce {
        var context = P2PBinaryWriter()
        context.uuid(sessionID)
        context.uint8(direction)
        let prefix = Data(SHA256.hash(data: context.data)).prefix(4)
        var bytes = Data(prefix)
        var writer = P2PBinaryWriter()
        writer.uint64(sequence)
        bytes.append(writer.data)
        return try ChaChaPoly.Nonce(data: bytes)
    }
}
