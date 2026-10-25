import Foundation
import Sparkle

/// Owns the strongly retained Sparkle controller and all update preferences.
/// No updater starts until production feed/key/security metadata validates.
@MainActor
final class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    private enum Keys {
        static let channel = "phase5.updates.channel"
        static let automaticChecks = "phase5.updates.automaticChecks"
        static let frequency = "phase5.updates.frequency"
    }

    @Published var channel: UpdateChannel {
        didSet {
            defaults.set(channel.rawValue, forKey: Keys.channel)
        }
    }
    @Published var automaticChecksEnabled: Bool {
        didSet {
            defaults.set(automaticChecksEnabled, forKey: Keys.automaticChecks)
            guard isStarted else { return }
            updaterController.updater.automaticallyChecksForUpdates = automaticChecksEnabled
        }
    }
    @Published var checkFrequency: UpdateCheckFrequency {
        didSet {
            defaults.set(checkFrequency.rawValue, forKey: Keys.frequency)
            guard isStarted else { return }
            updaterController.updater.updateCheckInterval = checkFrequency.interval
        }
    }
    @Published private(set) var availabilityMessage: String
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var releaseNotes: UpdateReleaseNotes?

    private let defaults: UserDefaults
    private let configuration: UpdateConfiguration?
    private var isStarted = false
    private var canCheckObservation: NSKeyValueObservation?

    var isConfigured: Bool { configuration != nil }

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        channel = UpdateChannel(rawValue: defaults.string(forKey: Keys.channel) ?? "") ?? .stable
        // Reading a missing Bool defaults to false. Sparkle's own first-run
        // prompt is disabled; this explicit setting is the only opt-in path.
        automaticChecksEnabled = defaults.object(forKey: Keys.automaticChecks) as? Bool ?? false
        checkFrequency = UpdateCheckFrequency(
            rawValue: defaults.string(forKey: Keys.frequency) ?? ""
        ) ?? .daily

        do {
            configuration = try UpdateConfiguration(bundle: bundle)
            availabilityMessage = "Signed updates are ready. Automatic checks are off unless you enable them."
        } catch {
            configuration = nil
            availabilityMessage = (error as? LocalizedError)?.errorDescription
                ?? "Updates are disabled in this build."
        }
        super.init()
    }

    func start() {
        guard !isStarted, configuration != nil else { return }
        // Apply opt-in state before starting Sparkle's first scheduled cycle.
        updaterController.updater.automaticallyChecksForUpdates = automaticChecksEnabled
        updaterController.updater.automaticallyDownloadsUpdates = false
        updaterController.updater.updateCheckInterval = checkFrequency.interval
        // Never allow a legacy/user-default feed to override the signed release
        // configuration returned by feedURLStringForUpdater below.
        _ = updaterController.updater.clearFeedURLFromUserDefaults()
        updaterController.startUpdater()
        isStarted = true
        canCheckForUpdates = updaterController.updater.canCheckForUpdates
        canCheckObservation = updaterController.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    func checkForUpdates() {
        start()
        guard isStarted else { return }
        updaterController.checkForUpdates(nil)
    }

    // MARK: - SPUUpdaterDelegate

    func feedURLString(for updater: SPUUpdater) -> String? {
        configuration?.feedURL.absoluteString
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        channel.allowedSparkleChannels
    }

    func feedParameters(
        for updater: SPUUpdater,
        sendingSystemProfile: Bool
    ) -> [[String: String]] {
        []
    }

    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String] {
        []
    }

    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        false
    }

    func updater(
        _ updater: SPUUpdater,
        shouldProceedWithUpdate updateItem: SUAppcastItem,
        updateCheck: SPUUpdateCheck
    ) throws {
        guard updateItem.signingValidationStatus == .succeeded else {
            throw UpdateConfigurationError.signedFeedRequired
        }
        guard HTTPSURLPolicy.isValid(updateItem.fileURL) else {
            throw UpdateConfigurationError.insecureFeed
        }
    }

    func updater(
        _ updater: SPUUpdater,
        shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem
    ) -> Bool {
        updateItem.signingValidationStatus == .succeeded
            && HTTPSURLPolicy.isValid(updateItem.releaseNotesURL)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        releaseNotes = UpdateReleaseNotes(item: item)
    }

    func updater(
        _ updater: SPUUpdater,
        willDownloadUpdate item: SUAppcastItem,
        with request: NSMutableURLRequest
    ) {
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 60
        request.setValue(nil, forHTTPHeaderField: "Cookie")
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    }
}
