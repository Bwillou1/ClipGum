import ClipGumCore
import Combine
import Foundation

@MainActor
final class CustomRulesViewModel: ObservableObject {
    @Published private(set) var rules: [CustomRule] = []
    @Published var selectedRuleID: UUID?
    @Published var draftName = ""
    @Published var draftKind: CustomRuleKind = .regex
    @Published var draftSource = ""
    @Published var draftReplacement = ""
    @Published var playgroundInput = ""
    @Published private(set) var playgroundOutput = ""
    @Published private(set) var statusMessage = ""
    @Published private(set) var isTesting = false

    let policy: EnterprisePolicyController
    /// App-owned adapters keep portable preferences separate from rule storage.
    var portableSettingsProvider: () -> PortableSettings = { PortableSettings() }
    var importSettingsHandler: (PortableSettings) -> Void = { _ in }
    private let repository: RuleRepository

    init(
        policy: EnterprisePolicyController,
        repository: RuleRepository = RuleRepository()
    ) {
        self.policy = policy
        self.repository = repository
        do {
            rules = try repository.load()
            selectedRuleID = rules.first?.id
        } catch {
            statusMessage = "Saved rules could not be loaded; no rule was executed."
        }
    }

    var selectedRule: CustomRule? {
        rules.first { $0.id == selectedRuleID }
    }

    var scriptsAllowed: Bool {
        policy.scriptsAllowed
    }

    func addRule() {
        policy.refresh()
        guard draftKind == .regex || policy.scriptsAllowed else {
            statusMessage = CustomRuleError.scriptDisabledByPolicy.localizedDescription
            return
        }
        let rule = CustomRule(
            name: draftName.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: draftKind,
            source: draftSource,
            replacement: draftReplacement
        )
        guard !rule.name.isEmpty else {
            statusMessage = CustomRuleError.invalidName.localizedDescription
            return
        }
        do {
            var updated = rules
            updated.append(rule)
            try RulePackCodec.validate(rules: updated)
            try repository.save(rules: updated)
            rules = updated
            selectedRuleID = rule.id
            draftName = ""
            draftSource = ""
            draftReplacement = ""
            statusMessage = "Rule saved locally. It runs only after an explicit test or transformation."
        } catch {
            statusMessage = safeMessage(error)
        }
    }

    func toggle(_ rule: CustomRule, enabled: Bool) {
        policy.refresh()
        if rule.kind == .script, enabled, !policy.scriptsAllowed {
            statusMessage = CustomRuleError.scriptDisabledByPolicy.localizedDescription
            return
        }
        update(rule) { $0.isEnabled = enabled }
    }

    func delete(_ rule: CustomRule) {
        var updated = rules
        updated.removeAll { $0.id == rule.id }
        persist(updated, message: "Rule deleted.")
        if selectedRuleID == rule.id { selectedRuleID = updated.first?.id }
    }

    func testSelected() {
        policy.refresh()
        guard let rule = selectedRule else {
            statusMessage = "Select a rule to test."
            return
        }
        guard rule.kind == .regex || policy.scriptsAllowed else {
            statusMessage = CustomRuleError.scriptDisabledByPolicy.localizedDescription
            return
        }
        let input = playgroundInput
        isTesting = true
        statusMessage = "Testing locally; no network or pasteboard access is available to the rule."
        Task {
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try CustomRuleEngine().apply(input, rules: [rule], allowScripts: true)
                }.value
                playgroundOutput = output
                statusMessage = "Test completed locally."
            } catch {
                playgroundOutput = ""
                statusMessage = safeMessage(error)
            }
            isTesting = false
        }
    }

    func importPack(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let imported = try repository.importPack(from: url)
            var merged = rules
            for rule in imported {
                if let index = merged.firstIndex(where: { $0.id == rule.id }) {
                    merged[index] = rule
                } else {
                    merged.append(rule)
                }
            }
            try RulePackCodec.validate(rules: merged)
            try repository.save(rules: merged)
            rules = merged
            selectedRuleID = imported.first?.id ?? selectedRuleID
            statusMessage = "Rule pack verified and imported. No imported script was executed."
        } catch {
            statusMessage = safeMessage(error)
        }
    }

    func exportPack(to url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            try repository.exportPack(rules: rules, to: url)
            statusMessage = "Checksummed rule pack exported."
        } catch {
            statusMessage = safeMessage(error)
        }
    }

    func exportBackup(to url: URL, password: String) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let payload = ClipGumBackupPayload(rules: rules, settings: portableSettingsProvider())
            let data = try LocalBackupArchive.export(payload: payload, password: password)
            try data.write(to: url, options: [.atomic])
            statusMessage = "Encrypted configuration exported. Audit confirmed no clipboard history or session mappings."
        } catch {
            statusMessage = safeMessage(error)
        }
    }

    func importBackup(from url: URL, password: String) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            policy.refresh()
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let fileSize = values.fileSize,
                  fileSize <= LocalBackupArchive.maximumArchiveBytes else {
                throw LocalBackupError.payloadTooLarge
            }
            let archive = try Data(contentsOf: url)
            let payload = try LocalBackupArchive.import(archive, password: password)
            var merged = rules
            for rule in payload.rules {
                if let index = merged.firstIndex(where: { $0.id == rule.id }) {
                    merged[index] = rule
                } else {
                    merged.append(rule)
                }
            }
            // Disabled imported scripts stay disabled under policy. Never run
            // imported source while decoding or applying preferences.
            for index in merged.indices where merged[index].kind == .script && !policy.scriptsAllowed {
                merged[index].isEnabled = false
            }
            try RulePackCodec.validate(rules: merged)
            try repository.save(rules: merged)
            rules = merged
            importSettingsHandler(payload.settings)
            selectedRuleID = payload.rules.first?.id ?? selectedRuleID
            statusMessage = "Encrypted configuration verified and imported. No imported script was executed."
        } catch {
            statusMessage = safeMessage(error)
        }
    }

    private func update(_ rule: CustomRule, mutate: (inout CustomRule) -> Void) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        var updated = rules
        mutate(&updated[index])
        persist(updated, message: "Rule updated.")
    }

    private func persist(_ updated: [CustomRule], message: String) {
        do {
            try repository.save(rules: updated)
            rules = updated
            statusMessage = message
        } catch {
            statusMessage = safeMessage(error)
        }
    }

    private func safeMessage(_ error: Error) -> String {
        if let error = error as? CustomRuleError, let description = error.errorDescription {
            return description
        }
        if let error = error as? DeterministicTransformError, let description = error.errorDescription {
            return description
        }
        if let error = error as? LocalBackupError, let description = error.errorDescription {
            return description
        }
        return "The rule operation failed safely; no content was logged."
    }
}
