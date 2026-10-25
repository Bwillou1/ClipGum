import Foundation

public enum P2PSessionState: Equatable, Sendable {
    case created
    case awaitingHello
    case awaitingConfirmation
    case awaitingReady
    case ready
    case closed
}

public enum P2PSessionEvent: Equatable, Sendable {
    case pairingCode(String)
    case ready
    case receivedSanitizedText(String)
    case deliveryAcknowledged(UUID)
    case closed
}

public struct P2PSessionOutput: Equatable, Sendable {
    public var outgoingFrames: [P2PFrame]
    public var events: [P2PSessionEvent]

    public init(outgoingFrames: [P2PFrame] = [], events: [P2PSessionEvent] = []) {
        self.outgoingFrames = outgoingFrames
        self.events = events
    }
}

private enum P2PMessageKind: UInt8 {
    case transfer = 1
    case acknowledgement = 2
    case ready = 3
}

private struct P2PTransferMessage {
    let id: UUID
    let text: Data

    func encode() throws -> Data {
        guard text.count <= P2PFrameCodec.maximumPayloadBytes else { throw P2PError.payloadTooLarge }
        var writer = P2PBinaryWriter()
        writer.uint8(P2PMessageKind.transfer.rawValue)
        writer.uuid(id)
        writer.uint32(UInt32(text.count))
        writer.bytes(text)
        return writer.data
    }

    static func decode(_ reader: inout P2PBinaryReader) throws -> P2PTransferMessage {
        let id = try reader.uuid()
        let length = Int(try reader.uint32())
        guard length <= P2PFrameCodec.maximumPayloadBytes else { throw P2PError.payloadTooLarge }
        return P2PTransferMessage(id: id, text: try reader.bytes(length))
    }
}

private struct P2PAcknowledgementMessage {
    let id: UUID

    func encode() -> Data {
        var writer = P2PBinaryWriter()
        writer.uint8(P2PMessageKind.acknowledgement.rawValue)
        writer.uuid(id)
        return writer.data
    }

    static func decode(_ reader: inout P2PBinaryReader) throws -> UUID {
        try reader.uuid()
    }
}

/// A single, explicit handoff session. It has no discovery, timer, pasteboard,
/// file, or history behavior. Callers drive it only from an active connection.
public struct P2PSession {
    public private(set) var state: P2PSessionState = .created
    private var pairing: P2PPairingSession
    private var channel: P2PSecureChannel?
    private var localConfirmed = false
    private var remoteConfirmed = false
    private var readySent = false
    private var readyReceived = false
    private var sendSequence: UInt64 = 0
    private var receiveSequence: UInt64 = 0
    private var pendingTransfer: UUID?

    public init(deviceName: String, isInitiator: Bool) throws {
        pairing = try P2PPairingSession(deviceName: deviceName, isInitiator: isInitiator)
    }

    public var pairingCode: String? { pairing.pairingCode }
    public var remoteDeviceName: String? { pairing.remoteDeviceName }
    public var hasPendingTransfer: Bool { pendingTransfer != nil }

    public mutating func start() throws -> P2PSessionOutput {
        guard state == .created else { throw P2PError.invalidTransition }
        state = .awaitingHello
        return P2PSessionOutput(outgoingFrames: [
            P2PFrame(kind: .hello, body: try pairing.localHello.encode())
        ])
    }

    public mutating func confirmPairing(code: String) throws -> P2PSessionOutput {
        guard state == .awaitingConfirmation || state == .awaitingReady,
              pairing.pairingCode == code, !localConfirmed else {
            throw P2PError.pairingCodeMismatch
        }
        localConfirmed = true
        var output = P2PSessionOutput(outgoingFrames: [try pairing.confirmation()])
        try makeReadyIfPossible(into: &output)
        return output
    }

    public mutating func sendSanitized(_ text: String) throws -> P2PSessionOutput {
        guard state == .ready, channel != nil, pendingTransfer == nil else {
            throw P2PError.pairingNotReady
        }
        // This second cleaning pass is intentional: callers cannot bypass the
        // P2P boundary with an uncleared preview or an LLM-generated string.
        let cleaned = DeterministicTransforms.sanitize(text).output
        var data = Data(cleaned.utf8)
        defer { wipeP2PData(&data) }
        guard data.count <= P2PFrameCodec.maximumPayloadBytes else {
            throw P2PError.payloadTooLarge
        }
        let id = UUID()
        var plaintext = try P2PTransferMessage(id: id, text: data).encode()
        defer { wipeP2PData(&plaintext) }
        let frame = try seal(plaintext)
        pendingTransfer = id
        return P2PSessionOutput(outgoingFrames: [frame])
    }

    public mutating func receive(_ frame: P2PFrame) throws -> P2PSessionOutput {
        guard state != .closed else { throw P2PError.connectionClosed }
        switch frame.kind {
        case .hello:
            guard state == .awaitingHello else { throw P2PError.invalidTransition }
            let hello = try P2PHello.decode(frame.body)
            let code = try pairing.receiveHello(hello)
            state = .awaitingConfirmation
            return P2PSessionOutput(events: [.pairingCode(code)])

        case .confirmation:
            guard state == .awaitingConfirmation || state == .awaitingReady,
                  !remoteConfirmed else {
                throw P2PError.invalidTransition
            }
            try pairing.validateConfirmation(frame)
            remoteConfirmed = true
            var output = P2PSessionOutput()
            try makeReadyIfPossible(into: &output)
            return output

        case .secure:
            guard let channel, localConfirmed, remoteConfirmed else {
                throw P2PError.pairingNotReady
            }
            guard receiveSequence < UInt64.max else { throw P2PError.replayDetected }
            var plaintext = try channel.open(frame, expectedSequence: receiveSequence)
            defer { wipeP2PData(&plaintext) }
            receiveSequence += 1
            return try receiveSecureMessage(plaintext)

        case .close:
            guard frame.body.isEmpty else { throw P2PError.malformedPacket }
            state = .closed
            channel = nil
            pendingTransfer = nil
            return P2PSessionOutput(events: [.closed])
        }
    }

    public mutating func close() throws -> P2PSessionOutput {
        guard state != .closed else { return P2PSessionOutput() }
        state = .closed
        channel = nil
        pendingTransfer = nil
        return P2PSessionOutput(
            outgoingFrames: [P2PFrame(kind: .close)],
            events: [.closed]
        )
    }

    private mutating func makeReadyIfPossible(into output: inout P2PSessionOutput) throws {
        guard localConfirmed, remoteConfirmed, channel == nil else { return }
        channel = try pairing.makeSecureChannel()
        let plaintext = Data([P2PMessageKind.ready.rawValue])
        output.outgoingFrames.append(try seal(plaintext))
        readySent = true
        state = .awaitingReady
    }

    private mutating func seal(_ plaintext: Data) throws -> P2PFrame {
        guard let channel else { throw P2PError.pairingNotReady }
        guard sendSequence < UInt64.max else { throw P2PError.replayDetected }
        let frame = try channel.seal(plaintext, sequence: sendSequence)
        sendSequence += 1
        return frame
    }

    private mutating func receiveSecureMessage(_ plaintext: Data) throws -> P2PSessionOutput {
        var reader = P2PBinaryReader(plaintext)
        guard let kind = P2PMessageKind(rawValue: try reader.uint8()) else {
            throw P2PError.malformedPacket
        }
        switch kind {
        case .ready:
            guard plaintext.count == 1, !readyReceived, readySent else {
                throw P2PError.invalidTransition
            }
            try reader.finish()
            readyReceived = true
            state = .ready
            return P2PSessionOutput(events: [.ready])

        case .transfer:
            guard state == .ready else { throw P2PError.pairingNotReady }
            let transfer = try P2PTransferMessage.decode(&reader)
            try reader.finish()
            guard let text = String(data: transfer.text, encoding: .utf8) else {
                throw P2PError.invalidUTF8
            }
            // Treat the peer's "sanitized" label as untrusted. Clean again
            // before making the value available to an extension or HUD preview.
            let cleaned = DeterministicTransforms.sanitize(text).output
            var output = P2PSessionOutput(events: [.receivedSanitizedText(cleaned)])
            output.outgoingFrames.append(try seal(P2PAcknowledgementMessage(id: transfer.id).encode()))
            return output

        case .acknowledgement:
            guard state == .ready else { throw P2PError.pairingNotReady }
            let id = try P2PAcknowledgementMessage.decode(&reader)
            try reader.finish()
            guard pendingTransfer == id else { throw P2PError.invalidTransition }
            pendingTransfer = nil
            return P2PSessionOutput(events: [.deliveryAcknowledged(id)])
        }
    }
}
