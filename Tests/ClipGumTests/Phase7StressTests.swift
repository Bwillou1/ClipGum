import Argon2
import ClipGumCore
import Foundation
import XCTest
@testable import ClipGum

final class Phase7CoreStressTests: XCTestCase {
    func test500UnicodeSanitizationCasesAreExactAndIdempotent() {
        for index in 0..<500 {
            let punctuation = index.isMultiple(of: 2) ? "" : ","
            let trackedURL = "https://example.com/path?utm_source=case&id=\(index)" + punctuation
            let plainURL = "https://example.com/path?id=\(index)"
            let unchanged = "préfixe-🙂-\(index) plain text"
            let input = [
                unchanged,
                "🙂 token=Abcd1234efgh5678 \(trackedURL)",
                plainURL,
                "Bearer Abcd1234efgh5678 192.168.1.\(index % 254 + 1)"
            ].joined(separator: "\n")
            let expected = [
                unchanged,
                "🙂 token=[REDACTED] https://example.com/path?id=\(index)" + punctuation,
                plainURL,
                "Bearer [REDACTED] [REDACTED]"
            ].joined(separator: "\n")

            let result = DeterministicTransforms.sanitize(input)
            XCTAssertEqual(result.output, expected, "sanitization case \(index)")
            XCTAssertEqual(result.changeCount, 4, "change count case \(index)")
            XCTAssertEqual(
                DeterministicTransforms.sanitize(result.output).output,
                expected,
                "idempotence case \(index)"
            )
        }
    }

    func test500FrameFragmentationCasesRoundTrip() {
        var random = StressRNG(seed: 0x43504c47)
        let kinds: [P2PFrameKind] = [.hello, .confirmation, .secure, .close]
        for index in 0..<500 {
            let frame = P2PFrame(
                kind: kinds[index % kinds.count],
                body: random.data(count: random.integer(upperBound: 257))
            )
            let packet: Data
            do {
                packet = try P2PFrameCodec.encode(frame)
            } catch {
                XCTFail("valid frame encoding failed for case \(index): \(error)")
                continue
            }
            let chunkSize = 1 + random.integer(upperBound: 31)
            var accumulator = P2PFrameAccumulator()
            var decoded: [P2PFrame] = []
            do {
                for start in stride(from: 0, to: packet.count, by: chunkSize) {
                    let end = min(start + chunkSize, packet.count)
                    decoded.append(contentsOf: try accumulator.append(packet.subdata(in: start..<end)))
                }
                XCTAssertEqual(decoded, [frame], "fragmentation case \(index)")
            } catch {
                XCTFail("fragmentation case \(index) failed: \(error)")
            }
            accumulator.wipe()
        }
    }

    func test500MalformedAndMutatedPacketsFailSafelyOrRoundTrip() {
        var random = StressRNG(seed: 0x5041434b4554)
        var accepted = 0
        for index in 0..<500 {
            let original = try? P2PFrameCodec.encode(P2PFrame(
                kind: .secure,
                body: random.data(count: 8 + random.integer(upperBound: 57))
            ))
            var packet = original ?? Data()
            switch index % 6 {
            case 0:
                if !packet.isEmpty {
                    let offset = random.integer(upperBound: packet.count)
                    packet[offset] ^= UInt8(1 << (index % 8))
                }
            case 1:
                packet = Data(packet.prefix(random.integer(upperBound: packet.count + 1)))
            case 2:
                packet.append(UInt8(truncatingIfNeeded: random.next()))
            case 3:
                if packet.count >= 4 {
                    packet[0] = UInt8(truncatingIfNeeded: random.next())
                    packet[1] = UInt8(truncatingIfNeeded: random.next())
                }
            case 4:
                break // Retain a known-valid frame in every mutation corpus.
            default:
                packet = random.data(count: random.integer(upperBound: 96))
            }

            do {
                let decoded = try P2PFrameCodec.decode(packet)
                XCTAssertEqual(try P2PFrameCodec.encode(decoded), packet, "canonical case \(index)")
                accepted += 1
            } catch {
                XCTAssertTrue(error is P2PError, "unexpected error for packet case \(index)")
            }
        }
        XCTAssertGreaterThan(accepted, 50, "the corpus must include valid decodes")
        XCTAssertThrowsError(try P2PFrameCodec.decode(Data(
            repeating: 0,
            count: P2PFrameCodec.maximumBufferedBytes + 1
        )))
    }

    func test64CompleteP2PSessionsDeliverAcknowledgeAndRejectReplay() throws {
        for index in 0..<64 {
            var pair = try makeStressPair(index: index)
            XCTAssertEqual(pair.initiator.state, .ready)
            XCTAssertEqual(pair.responder.state, .ready)
            let sent = try pair.initiator.sendSanitized(
                "🙂 token=Abcd1234efgh5678 https://example.com/?utm_source=x&id=\(index)"
            )
            let frame = try requiredStressFrame(sent)
            let received = try pair.responder.receive(frame)
            guard let event = received.events.first,
                  case .receivedSanitizedText(let text) = event else {
                XCTFail("missing received event for session \(index)")
                continue
            }
            XCTAssertFalse(text.contains("Abcd1234efgh5678"), "secret survived session \(index)")
            XCTAssertFalse(text.contains("utm_source"), "tracker survived session \(index)")
            let acknowledgement = try pair.initiator.receive(try requiredStressFrame(received))
            XCTAssertTrue(acknowledged.events.contains(where: {
                if case .deliveryAcknowledged = $0 { return true }
                return false
            }), "missing acknowledgement for session \(index)")
            XCTAssertFalse(pair.initiator.hasPendingTransfer)
            XCTAssertThrowsError(try pair.responder.receive(frame), "replay case \(index)") {
                XCTAssertEqual($0 as? P2PError, .replayDetected)
            }
        }
    }

    func test128BackupBitMutationsAreRejected() throws {
        let parameters = StressBackup.parameters
        let payload = ClipGumBackupPayload(rules: [
            CustomRule(name: "Synthetic", kind: .regex, source: "token-[0-9]+", replacement: "[x]")
        ])
        let password = "correct synthetic horse 🔐"
        let archive = try LocalBackupArchive.export(
            payload: payload,
            password: password,
            parameters: parameters
        )
        XCTAssertEqual(try LocalBackupArchive.import(archive, password: password), payload)

        for index in 0..<128 {
            var mutated = archive
            let offset = index % archive.count
            mutated[offset] ^= UInt8(1 << (index % 8))
            XCTAssertThrowsError(
                try LocalBackupArchive.import(mutated, password: password),
                "backup bit mutation case \(index)"
            )
        }
    }

    func test32EncryptedBackupRoundTrips() throws {
        for index in 0..<32 {
            let payload = ClipGumBackupPayload(
                rules: [CustomRule(
                    name: "Rule \(index)",
                    kind: .regex,
                    source: "token-\(index)",
                    replacement: "[x]",
                    isEnabled: !index.isMultiple(of: 2)
                )],
                settings: PortableSettings(
                    locale: index.isMultiple(of: 2) ? "en_CA" : nil,
                    temperature: [0.1, 0.2, 0.3][index % 3],
                    modelOffloadSeconds: 60 + index,
                    maximumOutputTokens: 64 + index,
                    telemetryEnabled: false,
                    mobileKeyboardEnabled: index.isMultiple(of: 2)
                )
            )
            let password = "correct synthetic password \(index) 🔐"
            let archive = try LocalBackupArchive.export(
                payload: payload,
                password: password,
                parameters: StressBackup.parameters
            )
            XCTAssertLessThanOrEqual(archive.count, LocalBackupArchive.maximumArchiveBytes)
            XCTAssertEqual(
                try LocalBackupArchive.import(archive, password: password),
                payload,
                "backup round trip case \(index)"
            )
            if index.isMultiple(of: 8) {
                XCTAssertThrowsError(try LocalBackupArchive.import(
                    archive,
                    password: "incorrect synthetic password"
                ))
            }
        }
    }

    func test500BackupSchemaMutationsAreRejected() throws {
        let payload = ClipGumBackupPayload(rules: [
            CustomRule(name: "Literal clipboard regex", kind: .regex, source: "clipboard|token")
        ])
        let valid = try JSONEncoder().encode(payload)
        try LocalBackupArchive.audit(valid)
        let baseline = try XCTUnwrap(
            JSONSerialization.jsonObject(with: valid) as? [String: Any]
        )
        let requiredSettings = [
            "temperature", "modelOffloadSeconds", "maximumOutputTokens",
            "telemetryEnabled", "mobileKeyboardEnabled"
        ]

        for index in 0..<500 {
            var object = baseline
            switch index % 8 {
            case 0:
                let keys = ["clipboardHistory", "pasteboard", "sessionMappings", "privateKey", "extra"]
                object[keys[(index / 8) % keys.count]] = ["synthetic"]
            case 1:
                var settings = try XCTUnwrap(object["settings"] as? [String: Any])
                settings["unexpectedSetting"] = true
                object["settings"] = settings
            case 2:
                var rules = try XCTUnwrap(object["rules"] as? [[String: Any]])
                rules[0]["originalText"] = "synthetic"
                object["rules"] = rules
            case 3:
                var settings = try XCTUnwrap(object["settings"] as? [String: Any])
                settings.removeValue(forKey: requiredSettings[(index / 8) % requiredSettings.count])
                object["settings"] = settings
            case 4:
                object["schemaVersion"] = 2
            case 5:
                object["rules"] = "not-an-array"
            case 6:
                object["settings"] = [String]()
            default:
                object.removeValue(forKey: "settings")
            }
            let data = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try LocalBackupArchive.audit(data), "schema mutation case \(index)") {
                XCTAssertEqual($0 as? LocalBackupError, .unsafeConfiguration)
            }
        }
    }
}

final class Phase7AppStressTests: XCTestCase {
    func test250MacCleanerCasesPreservePublicIPsAndUnicode() {
        let cleaner = RuleCleaningService()
        for index in 0..<250 {
            let publicIP = "8.8.8.\(index % 254 + 1)"
            let privateIP = "10.0.0.\(index % 254 + 1)"
            let input = "🙂 token=Abcd1234efgh5678 https://example.com/?utm_source=x&id=\(index) \(publicIP) \(privateIP)"
            let expected = "🙂 token=[SECRET_REDACTED] https://example.com/?id=\(index) \(publicIP) [SECRET_REDACTED]"
            let result = cleaner.clean(input)
            XCTAssertEqual(result.cleaned, expected, "mac cleaner case \(index)")
            XCTAssertEqual(result.removedTrackingParameters, 1)
            XCTAssertEqual(result.redactedSecrets, 2)
            XCTAssertEqual(cleaner.clean(expected).cleaned, expected, "mac idempotence case \(index)")
        }
    }
}

private enum StressBackup {
    static let parameters = Argon2Params(
        variant: .id,
        timeCost: 1,
        memoryCostKilobytes: 32,
        parallelism: 4,
        outputLength: 32
    )
}

private enum StressTestError: Error {
    case missingFrame
}

private func requiredStressFrame(_ output: P2PSessionOutput, _ index: Int = 0) throws -> P2PFrame {
    guard output.outgoingFrames.indices.contains(index) else { throw StressTestError.missingFrame }
    return output.outgoingFrames[index]
}

private func makeStressPair(index: Int) throws -> (initiator: P2PSession, responder: P2PSession) {
    var initiator = try P2PSession(deviceName: "Mac \(index)", isInitiator: true)
    var responder = try P2PSession(deviceName: "iPad \(index)", isInitiator: false)
    let initiatorStart = try initiator.start()
    let responderStart = try responder.start()
    _ = try responder.receive(try requiredStressFrame(initiatorStart))
    _ = try initiator.receive(try requiredStressFrame(responderStart))
    guard let code = initiator.pairingCode, initiator.pairingCode == responder.pairingCode else {
        throw StressTestError.missingFrame
    }
    let initiatorConfirmation = try initiator.confirmPairing(code: code)
    _ = try responder.receive(try requiredStressFrame(initiatorConfirmation))
    let responderConfirmation = try responder.confirmPairing(code: code)
    let initiatorReady = try initiator.receive(try requiredStressFrame(responderConfirmation, 0))
    _ = try initiator.receive(try requiredStressFrame(responderConfirmation, 1))
    _ = try responder.receive(try requiredStressFrame(initiatorReady))
    return (initiator, responder)
}

private struct StressRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func integer(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next() % UInt64(upperBound))
    }

    mutating func data(count: Int) -> Data {
        Data((0..<count).map { _ in UInt8(truncatingIfNeeded: next()) })
    }
}
