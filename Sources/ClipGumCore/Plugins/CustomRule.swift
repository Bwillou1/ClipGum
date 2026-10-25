import Foundation

public enum CustomRuleKind: String, Codable, Sendable {
    case regex
    case script
}

public struct CustomRule: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: CustomRuleKind
    public var source: String
    public var replacement: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        kind: CustomRuleKind,
        source: String,
        replacement: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.source = source
        self.replacement = replacement
        self.isEnabled = isEnabled
    }
}

public enum CustomRuleError: LocalizedError, Equatable, Sendable {
    case invalidName
    case invalidExpression
    case invalidScript
    case missingMainFunction
    case scriptDisabledByPolicy
    case executionTimedOut
    case memoryBudgetExceeded
    case watchdogUnavailable
    case scriptFailed
    case nonStringResult
    case inputTooLarge
    case outputTooLarge
    case sourceTooLarge
    case tooManyRules
    case invalidRulePack
    case checksumMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidName: return "Enter a rule name."
        case .invalidExpression: return "The regular expression is invalid."
        case .invalidScript, .scriptFailed: return "The script could not be evaluated safely."
        case .missingMainFunction: return "The script must define main(input) and return a string."
        case .scriptDisabledByPolicy: return "Custom scripts are disabled by the managed enterprise policy."
        case .executionTimedOut: return "The script exceeded the 250 ms execution budget."
        case .memoryBudgetExceeded: return "The script exceeded the 16 MB memory budget."
        case .watchdogUnavailable: return "This macOS runtime cannot enforce the script watchdog; execution was blocked."
        case .nonStringResult: return "main(input) must return a string."
        case .inputTooLarge: return "The rule input is too large."
        case .outputTooLarge: return "The rule output is too large."
        case .sourceTooLarge: return "The rule source is too large."
        case .tooManyRules: return "A rule pack contains too many rules."
        case .invalidRulePack: return "The rule pack schema is invalid."
        case .checksumMismatch: return "The rule pack integrity checksum does not match."
        }
    }
}
