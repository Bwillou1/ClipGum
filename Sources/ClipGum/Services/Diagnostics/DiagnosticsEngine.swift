import Foundation

/// Volatile, opt-in, non-content counters. There is deliberately no telemetry
/// session, uploader, endpoint, free-form event name, or free-form error text.
@MainActor
final class DiagnosticsEngine: ObservableObject {
    private enum Keys {
        static let enabled = "phase5.diagnostics.enabled"
    }
    private static let maximumLatencySamplesPerFeature = 256

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isTelemetryLocked: Bool
    @Published private(set) var snapshot = DiagnosticsSnapshot(
        features: [:],
        errors: [:],
        peakResidentMemoryBytes: 0
    )

    private let defaults: UserDefaults
    private let memoryProvider: () -> UInt64?
    private let clock: () -> Date

    init(
        defaults: UserDefaults = .standard,
        memoryProvider: @escaping () -> UInt64? = { ProcessMemoryUsage.residentBytes() },
        clock: @escaping () -> Date = { Date() },
        telemetryLocked: Bool = false
    ) {
        self.defaults = defaults
        self.memoryProvider = memoryProvider
        self.clock = clock
        isTelemetryLocked = telemetryLocked
        isEnabled = telemetryLocked ? false : (defaults.object(forKey: Keys.enabled) as? Bool ?? false)
    }

    func applyPolicy(lockTelemetry: Bool) {
        isTelemetryLocked = lockTelemetry
        if lockTelemetry { clearAllData() }
    }

    func setEnabled(_ enabled: Bool) {
        guard !isTelemetryLocked else {
            clearAllData()
            return
        }
        guard enabled else {
            clearAllData()
            return
        }
        defaults.set(true, forKey: Keys.enabled)
        isEnabled = true
    }

    func record(
        feature: DiagnosticFeature,
        latencyNanoseconds: UInt64,
        error: DiagnosticErrorCode? = nil
    ) {
        guard isEnabled else { return }

        var features = snapshot.features
        var metrics = features[feature] ?? DiagnosticFeatureMetrics()
        metrics.activationCount += 1
        metrics.latencySamples.append(latencyNanoseconds / 1_000_000)
        if metrics.latencySamples.count > Self.maximumLatencySamplesPerFeature {
            metrics.latencySamples.removeFirst(
                metrics.latencySamples.count - Self.maximumLatencySamplesPerFeature
            )
        }
        features[feature] = metrics

        var errors = snapshot.errors
        if let error {
            errors[error, default: 0] += 1
        }
        let residentBytes = memoryProvider() ?? 0
        snapshot = DiagnosticsSnapshot(
            features: features,
            errors: errors,
            peakResidentMemoryBytes: max(snapshot.peakResidentMemoryBytes, residentBytes)
        )
    }

    func payloadData() throws -> Data {
        let features = snapshot.features.compactMap { feature, metrics -> DiagnosticFeaturePayload? in
            guard metrics.activationCount > 0 else { return nil }
            let sorted = metrics.latencySamples.sorted()
            return DiagnosticFeaturePayload(
                feature: feature,
                activationCount: metrics.activationCount,
                p50LatencyMilliseconds: Self.percentile(0.50, sorted: sorted),
                p95LatencyMilliseconds: Self.percentile(0.95, sorted: sorted)
            )
        }.sorted { $0.feature.rawValue < $1.feature.rawValue }
        let errors = snapshot.errors.map { error, count in
            DiagnosticErrorPayload(error: error, count: count)
        }.sorted { $0.error.rawValue < $1.error.rawValue }
        let payload = DiagnosticPayload(
            schemaVersion: 1,
            generatedAt: clock(),
            features: features,
            errors: errors,
            peakResidentMemoryBytes: snapshot.peakResidentMemoryBytes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try DiagnosticPayloadSchema.validate(data)
        return data
    }

    func payloadText() throws -> String {
        String(decoding: try payloadData(), as: UTF8.self)
    }

    /// One action clears every diagnostic value and withdraws opt-in. ClipGum's
    /// preview/Share-Ready/Chain data is cleared by the same Preferences action.
    func clearAllData() {
        defaults.removeObject(forKey: Keys.enabled)
        isEnabled = false
        snapshot = DiagnosticsSnapshot(features: [:], errors: [:], peakResidentMemoryBytes: 0)
    }

    private static func percentile(_ percentile: Double, sorted: [UInt64]) -> UInt64 {
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((Double(sorted.count) * percentile).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }
}
