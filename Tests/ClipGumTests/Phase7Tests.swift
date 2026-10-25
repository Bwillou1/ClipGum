import Argon2
import ClipGumCore
import Foundation
import XCTest

final class Phase7P2PTests: XCTestCase {
    func testMutualPairingSanitizedHandoffAndAcknowledgement() throws {
        var initiator = try P2PSession(deviceName: "Mac", isInitiator: true)
        var responder = try P2PSession(deviceName: "iPad", isInitiator: false)
        let initiatorStart = try initiator.start()
        let responderStart = try responder.start()

        let responderHello = try responder.receive(try XCTUnwrap(initiatorStart.outgoingFrames.first))
        let initiatorHello = try initiator.receive(try XCTUnwrap(responderStart.outgoingFrames.first))
        let responderCode = try XCTUnwrap(responderHello.events.first)
        let initiatorCode = try XCTUnwrap(initiatorHello.events.first)
        guard case .pairingCode(let codeA) = responderCode,
              case .pairingCode(let codeB) = initiatorCode else {
            return XCTFail("Expected matching pairing codes")
        }
        XCTAssertEqual(codeA, codeB)
        XCTAssertEqual(codeA.count, 6)

        let initiatorConfirmation = try initiator.confirmPairing(code: codeA)
        _ = try responder.receive(try XCTUnwrap(initiatorConfirmation.outgoingFrames.first))
        let responderConfirmation = try responder.confirmPairing(code: codeB)
        let initiatorReady = try initiator.receive(try XCTUnwrap(responderConfirmation.outgoingFrames.first))
        XCTAssertEqual(responderConfirmation.outgoingFrames.count, 2)
        _ = try initiator.receive(responderConfirmation.outgoingFrames[1])
        let responderReady = try responder.receive(try XCTUnwrap(initiatorReady.outgoingFrames.first))
        XCTAssertEqual(initiator.state, .ready)
        XCTAssertEqual(responder.state, .ready)
        XCTAssertTrue(responderReady.events.contains(.ready))

        let sent = try initiator.sendSanitized(
            "token=Abcd1234efgh5678 https://example.com/?utm_source=test&id=1"
        )
        XCTAssertTrue(initiator.hasPendingTransfer)
        let received = try responder.receive(try XCTUnwrap(sent.outgoingFrames.first))
        guard let event = received.events.first,
              case .receivedSanitizedText(let text) = event else {
            return XCTFail("Expected a sanitized handoff")
        }
        XCTAssertFalse(text.contains("Abcd1234efgh5678"))
        XCTAssertFalse(text.contains("utm_source"))
        XCTAssertEqual(received.outgoingFrames.count, 1)
        let acknowledged = try initiator.receive(try XCTUnwrap(received.outgoingFrames.first))
        XCTAssertTrue(acknowledged.events.contains(where: {
            if case .deliveryAcknowledged = $0 { return true }; return false
        }))
        XCTAssertFalse(initiator.hasPendingTransfer)
    }

    func testUnpairedAndMalformedPacketsAreRejected() throws {
        var session = try P2PSession(deviceName: "Mac", isInitiator: true)
        _ = try session.start()
        XCTAssertThrowsError(try session.sendSanitized("secret"))
        XCTAssertThrowsError(try session.receive(P2PFrame(kind: .secure, body: Data([1, 2, 3]))))
        XCTAssertThrowsError(try P2PFrameCodec.decode(Data([0, 0, 0, 1, 99])))
        XCTAssertThrowsError(try P2PFrameCodec.decode(Data([0, 0, 0, 2, 1])))

        var accumulator = P2PFrameAccumulator()
        let frame = try P2PFrame(kind: .close).pipeFrame()
        let firstHalf = frame.prefix(2)
        let secondHalf = frame.suffix(frame.count - 2)
        XCTAssertTrue(try accumulator.append(firstHalf).isEmpty)
        XCTAssertEqual(try accumulator.append(secondHalf), [P2PFrame(kind: .close)])
    }

    func testTamperingReplayAndCloseFailClosed() throws {
        var pair = try PairedSessions()
        let sent = try pair.initiator.sendSanitized("hello")
        var tampered = try XCTUnwrap(sent.outgoingFrames.first)
        var body = tampered.body
        body[body.index(before: body.endIndex)] ^= 0x01
        tampered = P2PFrame(kind: tampered.kind, body: body)
        XCTAssertThrowsError(try pair.responder.receive(tampered)) { error in
            XCTAssertEqual(error as? P2PError, .authenticationFailed)
        }

        let closed = try pair.initiator.close()
        let remoteClose = try pair.responder.receive(try XCTUnwrap(closed.outgoingFrames.first))
        XCTAssertEqual(pair.responder.state, .closed)
        XCTAssertTrue(remoteClose.events.contains(.closed))
        XCTAssertThrowsError(try pair.responder.receive(P2PFrame(kind: .close)))
    }

    func testWrongPairingCodeCannotConfirm() throws {
        var initiator = try P2PSession(deviceName: "Mac", isInitiator: true)
        var responder = try P2PSession(deviceName: "iPad", isInitiator: false)
        let a = try initiator.start()
        let b = try responder.start()
        _ = try responder.receive(try XCTUnwrap(a.outgoingFrames.first))
        _ = try initiator.receive(try XCTUnwrap(b.outgoingFrames.first))
        let actualCode = try XCTUnwrap(initiator.pairingCode)
        let wrongCode = actualCode == "000000" ? "000001" : "000000"
        XCTAssertThrowsError(try initiator.confirmPairing(code: wrongCode)) { error in
            XCTAssertEqual(error as? P2PError, .pairingCodeMismatch)
        }
    }
}

final class Phase7BackupTests: XCTestCase {
    private let testParameters = Argon2Params(
        variant: .id, timeCost: 1, memoryCostKilobytes: 32, parallelism: 4, outputLength: 32
    )

    func testRFC9106Argon2idVector() throws {
        let password = Data(repeating: 0x01, count: 32)
        let salt = Data(repeating: 0x02, count: 16)
        let secret = Data(repeating: 0x03, count: 8)
        let associatedData = Data(repeating: 0x04, count: 12)
        let parameters = Argon2Params(
            variant: .id, timeCost: 3, memoryCostKilobytes: 32, parallelism: 4, outputLength: 32
        )
        let tag = try Argon2.deriveKey(
            password: password, salt: salt, secret: secret,
            associatedData: associatedData, params: parameters
        )
        XCTAssertEqual(tag.hexString, "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659")
    }

    func testEncryptedBackupRoundTripAuditAndTamperRejection() throws {
        let rule = CustomRule(name: "Trim", kind: .regex, source: "\\s+", replacement: " ")
        let payload = ClipGumBackupPayload(
            rules: [rule],
            settings: PortableSettings(locale: "en_CA", telemetryEnabled: false)
        )
        let archive = try LocalBackupArchive.export(
            payload: payload, password: "correct horse battery staple", parameters: testParameters
        )
        XCTAssertEqual(try LocalBackupArchive.import(
            archive, password: "correct horse battery staple"
        ), payload)
        let report = try LocalBackupArchive.auditReport(for: payload)
        XCTAssertFalse(report.includesClipboardHistory)
        XCTAssertFalse(report.includesSessionMappings)

        XCTAssertThrowsError(try LocalBackupArchive.import(archive, password: "wrong password")) { error in
            XCTAssertEqual(error as? LocalBackupError, .authenticationFailed)
        }
        var modified = archive
        modified[modified.index(before: modified.endIndex)] ^= 0x80
        XCTAssertThrowsError(try LocalBackupArchive.import(
            modified, password: "correct horse battery staple"
        )) { error in
            XCTAssertEqual(error as? LocalBackupError, .authenticationFailed)
        }
    }

    func testBackupAuditRejectsHistoryAndUnsafeKDFParameters() throws {
        let malicious = Data(#"{"schemaVersion":1,"rules":[],"settings":{},"clipboardHistory":["secret"]}"#.utf8)
        XCTAssertThrowsError(try LocalBackupArchive.audit(malicious)) { error in
            XCTAssertEqual(error as? LocalBackupError, .unsafeConfiguration)
        }
        let payload = ClipGumBackupPayload(rules: [])
        let archive = try LocalBackupArchive.export(
            payload: payload, password: "correct horse battery staple", parameters: testParameters
        )
        var maliciousParameters = archive
        // Memory cost is at offset 12 in the fixed header; an excessive value
        // must be rejected before Argon2 allocates memory.
        maliciousParameters[12] = 0x7f
        XCTAssertThrowsError(try LocalBackupArchive.import(
            maliciousParameters, password: "correct horse battery staple"
        )) { error in
            XCTAssertEqual(error as? LocalBackupError, .invalidParameters)
        }
    }

    func testMobileAdapterUsesDeterministicCore() throws {
        let result = MobileCleaningService().clean(
            "https://example.com/?utm_source=x&id=1 token=Abcd1234efgh5678"
        )
        XCTAssertEqual(result.output, "https://example.com/?id=1 token=[REDACTED]")
        XCTAssertEqual(try MobileCleaningService().extractTable("a;b\n1;2"), "a,b\n1,2")
    }
}

private struct PairedSessions {
    var initiator: P2PSession
    var responder: P2PSession

    init() throws {
        initiator = try P2PSession(deviceName: "Mac", isInitiator: true)
        responder = try P2PSession(deviceName: "iPad", isInitiator: false)
        let a = try initiator.start()
        let b = try responder.start()
        _ = try responder.receive(a.outgoingFrames[0])
        _ = try initiator.receive(b.outgoingFrames[0])
        let code = try XCTUnwrap(initiator.pairingCode)
        let ac = try initiator.confirmPairing(code: code)
        _ = try responder.receive(ac.outgoingFrames[0])
        let bc = try responder.confirmPairing(code: code)
        let ar = try initiator.receive(bc.outgoingFrames[0])
        _ = try initiator.receive(bc.outgoingFrames[1])
        _ = try responder.receive(ar.outgoingFrames[0])
    }
}

private extension P2PFrame {
    func pipeFrame() throws -> Data { try P2PFrameCodec.encode(self) }
}

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
