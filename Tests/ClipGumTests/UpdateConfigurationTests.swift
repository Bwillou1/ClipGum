import Foundation
import XCTest
@testable import ClipGum

@MainActor
final class UpdateConfigurationTests: XCTestCase {
    private let key = Data(repeating: 0x42, count: 32).base64EncodedString()

    func testValidProductionConfigurationAndChannels() throws {
        let configuration = try UpdateConfiguration(
            feedURLString: "https://updates.example.com/clipgum.xml",
            publicEDKey: key
        )
        XCTAssertEqual(configuration.feedURL.host, "updates.example.com")
        XCTAssertEqual(UpdateChannel.stable.allowedSparkleChannels, [])
        XCTAssertEqual(UpdateChannel.beta.allowedSparkleChannels, ["beta"])
        XCTAssertEqual(UpdateCheckFrequency.daily.interval, 86_400)
        XCTAssertEqual(UpdateCheckFrequency.weekly.interval, 604_800)
    }

    func testMissingOrInsecureFeedFailsClosed() {
        XCTAssertThrowsError(try UpdateConfiguration(feedURLString: nil, publicEDKey: key)) {
            XCTAssertEqual($0 as? UpdateConfigurationError, .missingFeed)
        }
        for url in ["http://updates.example.com/feed.xml", "file:///tmp/feed.xml", "https://user:pass@example.com/feed.xml"] {
            XCTAssertThrowsError(try UpdateConfiguration(feedURLString: url, publicEDKey: key)) {
                XCTAssertEqual($0 as? UpdateConfigurationError, .insecureFeed)
            }
        }
    }

    func testMissingShortAndMalformedEdKeysFailClosed() {
        for invalid in [nil, "", "not-base64", Data(repeating: 1, count: 31).base64EncodedString()] as [String?] {
            XCTAssertThrowsError(try UpdateConfiguration(
                feedURLString: "https://updates.example.com/feed.xml",
                publicEDKey: invalid
            ))
        }
    }

    func testSignedFeedAndPreExtractionVerificationAreMandatory() {
        XCTAssertThrowsError(try UpdateConfiguration(
            feedURLString: "https://updates.example.com/feed.xml",
            publicEDKey: key,
            requiresSignedFeed: false
        )) { XCTAssertEqual($0 as? UpdateConfigurationError, .signedFeedRequired) }
        XCTAssertThrowsError(try UpdateConfiguration(
            feedURLString: "https://updates.example.com/feed.xml",
            publicEDKey: key,
            verifiesBeforeExtraction: false
        )) { XCTAssertEqual($0 as? UpdateConfigurationError, .verificationBeforeExtractionRequired) }
    }

    func testNetworkClientCannotEnableSparkleDownloaderXPC() {
        XCTAssertThrowsError(try UpdateConfiguration(
            feedURLString: "https://updates.example.com/feed.xml",
            publicEDKey: key,
            downloaderServiceEnabled: true
        )) { XCTAssertEqual($0 as? UpdateConfigurationError, .downloaderServiceConflict) }
    }

    func testHTTPSPolicyRejectsUserinfoAndNonHTTPS() {
        XCTAssertTrue(HTTPSURLPolicy.isValid(string: "https://example.com/models/a.gguf"))
        XCTAssertFalse(HTTPSURLPolicy.isValid(string: "https://user@example.com/a"))
        XCTAssertTrue(HTTPSURLPolicy.isValid(string: "https://example.com"))
        XCTAssertFalse(HTTPSURLPolicy.isValid(string: "ftp://example.com/a"))
    }

    func testUpdatePreferencesDefaultToStableManualDaily() {
        let suite = "ClipGumTests.Updates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = UpdateManager(defaults: defaults, bundle: .main)
        XCTAssertEqual(manager.channel, .stable)
        XCTAssertFalse(manager.automaticChecksEnabled)
        XCTAssertEqual(manager.checkFrequency, .daily)

        manager.channel = .beta
        manager.automaticChecksEnabled = true
        manager.checkFrequency = .weekly
        XCTAssertEqual(defaults.string(forKey: "phase5.updates.channel"), "beta")
        XCTAssertTrue(defaults.bool(forKey: "phase5.updates.automaticChecks"))
        XCTAssertEqual(defaults.string(forKey: "phase5.updates.frequency"), "weekly")
    }
}
