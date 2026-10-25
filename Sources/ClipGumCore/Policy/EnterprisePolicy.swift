import CoreFoundation
import Foundation

public enum ManagedPolicyKey: String, CaseIterable, Sendable {
    case disableExternalLLM = "DisableExternalLLM"
    case forceSecretRedaction = "ForceSecretRedaction"
    case disableCustomScripts = "DisableCustomScripts"
    case lockTelemetry = "LockTelemetry"
}

public struct EnterprisePolicy: Equatable, Sendable {
    public let values: [ManagedPolicyKey: Bool]
    public let forcedKeys: Set<ManagedPolicyKey>

    public init(values: [ManagedPolicyKey: Bool] = [:], forcedKeys: Set<ManagedPolicyKey> = []) {
        self.values = values
        self.forcedKeys = forcedKeys
    }

    public func value(_ key: ManagedPolicyKey) -> Bool {
        values[key] ?? false
    }

    public func isForced(_ key: ManagedPolicyKey) -> Bool {
        forcedKeys.contains(key)
    }

    public var disableExternalLLM: Bool { value(.disableExternalLLM) }
    public var forceSecretRedaction: Bool { value(.forceSecretRedaction) }
    public var disableCustomScripts: Bool { value(.disableCustomScripts) }
    public var lockTelemetry: Bool { value(.lockTelemetry) }

    public var lockedLabels: [String] {
        ManagedPolicyKey.allCases.filter { isForced($0) && value($0) }.map {
            switch $0 {
            case .disableExternalLLM: return "Local inference locked"
            case .forceSecretRedaction: return "Secret redaction enforced"
            case .disableCustomScripts: return "Custom scripts disabled"
            case .lockTelemetry: return "Telemetry locked off"
            }
        }
    }
}

/// A read-only abstraction makes managed-preference behavior testable without
/// writing a real macOS profile. Production uses CFPreferences, which includes
/// the managed (/Library/Managed Preferences) domain and forced-key metadata.
public protocol PolicyStore: AnyObject {
    func object(forKey key: String) -> Any?
    func isForced(_ key: String) -> Bool
}

public final class CFPreferencesPolicyStore: PolicyStore {
    private let bundleIdentifier: String

    public init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.clipgum.ClipGum") {
        self.bundleIdentifier = bundleIdentifier
    }

    public func object(forKey key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, bundleIdentifier as CFString)
    }

    public func isForced(_ key: String) -> Bool {
        CFPreferencesAppValueIsForced(key as CFString, bundleIdentifier as CFString)
    }
}

/// Test and non-production store. It never writes values itself; callers may
/// populate a UserDefaults suite to model a managed profile.
public final class UserDefaultsPolicyStore: PolicyStore {
    private let defaults: UserDefaults
    private let forced: Set<String>

    public init(defaults: UserDefaults, forcedKeys: Set<String> = []) {
        self.defaults = defaults
        forced = forcedKeys
    }

    public func object(forKey key: String) -> Any? {
        defaults.object(forKey: key)
    }

    public func isForced(_ key: String) -> Bool {
        forced.contains(key)
    }
}

public final class PolicyCenter {
    private let store: PolicyStore

    public init(store: PolicyStore = CFPreferencesPolicyStore()) {
        self.store = store
    }

    /// Reads on demand only. There is no preference timer, watcher, or polling
    /// loop, so a quiescent app has no policy-related background work.
    public func snapshot() -> EnterprisePolicy {
        var values: [ManagedPolicyKey: Bool] = [:]
        var forced: Set<ManagedPolicyKey> = []
        for key in ManagedPolicyKey.allCases {
            values[key] = (store.object(forKey: key.rawValue) as? Bool) ?? false
            if store.isForced(key.rawValue) { forced.insert(key) }
        }
        return EnterprisePolicy(values: values, forcedKeys: forced)
    }
}
