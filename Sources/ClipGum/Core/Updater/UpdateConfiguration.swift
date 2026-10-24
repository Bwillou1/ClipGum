import CryptoKit
import Foundation

enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case beta

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stable: return "Stable"
        case .beta: return "Beta"
        }
    }

    /// Sparkle always includes the default (stable) channel. Beta explicitly
    /// adds only the named beta channel; no wildcard channel is supported.
    var allowedSparkleChannels: Set<String> {
        switch self {
        case .stable: return []
        case .beta: return ["beta"]
        }
    }
}

enum UpdateCheckFrequency: String, CaseIterable, Identifiable {
    case daily
    case weekly

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var interval: TimeInterval {
        switch self {
        case .daily: return 86_400
        case .weekly: return 604_800
        }
    }
}

enum UpdateConfigurationError: LocalizedError, Equatable {
    case missingFeed
    case insecureFeed
    case missingPublicKey
    case invalidPublicKey
    case signedFeedRequired
    case verificationBeforeExtractionRequired
    case downloaderServiceConflict

    var errorDescription: String? {
        switch self {
        case .missingFeed, .insecureFeed:
            return "This build has no valid strict-HTTPS update feed. Updates remain disabled."
        case .missingPublicKey, .invalidPublicKey:
            return "This build has no valid 32-byte Ed25519 update key. Updates remain disabled."
        case .signedFeedRequired, .verificationBeforeExtractionRequired:
            return "This build does not enforce signed feeds and pre-extraction verification. Updates remain disabled."
        case .downloaderServiceConflict:
            return "This build enables conflicting Sparkle downloader access. Updates remain disabled."
        }
    }
}

struct UpdateConfiguration: Equatable {
    let feedURL: URL
    let publicEDKey: String

    init(
        feedURLString: String?,
        publicEDKey: String?,
        requiresSignedFeed: Bool = true,
        verifiesBeforeExtraction: Bool = true,
        downloaderServiceEnabled: Bool = false
    ) throws {
        guard let feedURLString, !feedURLString.isEmpty else {
            throw UpdateConfigurationError.missingFeed
        }
        guard HTTPSURLPolicy.isValid(string: feedURLString), let feedURL = URL(string: feedURLString) else {
            throw UpdateConfigurationError.insecureFeed
        }
        guard let publicEDKey, !publicEDKey.isEmpty else {
            throw UpdateConfigurationError.missingPublicKey
        }
        guard Self.isValidEd25519PublicKey(publicEDKey) else {
            throw UpdateConfigurationError.invalidPublicKey
        }
        guard requiresSignedFeed else {
            throw UpdateConfigurationError.signedFeedRequired
        }
        guard verifiesBeforeExtraction else {
            throw UpdateConfigurationError.verificationBeforeExtractionRequired
        }
        // ClipGum's explicit model downloader requires main-app network client.
        // Sparkle documents that this combination must not use its downloader XPC.
        guard !downloaderServiceEnabled else {
            throw UpdateConfigurationError.downloaderServiceConflict
        }
        self.feedURL = feedURL
        self.publicEDKey = publicEDKey
    }

    init(bundle: Bundle) throws {
        let values = bundle.infoDictionary ?? [:]
        try self.init(
            feedURLString: values["SUFeedURL"] as? String,
            publicEDKey: values["SUPublicEDKey"] as? String,
            requiresSignedFeed: values["SURequireSignedFeed"] as? Bool == true,
            verifiesBeforeExtraction: values["SUVerifyUpdateBeforeExtraction"] as? Bool == true,
            downloaderServiceEnabled: values["SUEnableDownloaderService"] as? Bool == true
        )
    }

    static func isValidEd25519PublicKey(_ key: String) -> Bool {
        guard
            key.range(of: "^[A-Za-z0-9+/]{43}=$", options: .regularExpression) != nil,
            let data = Data(base64Encoded: key),
            data.count == 32
        else {
            return false
        }
        return (try? Curve25519.Signing.PublicKey(rawRepresentation: data)) != nil
    }
}
