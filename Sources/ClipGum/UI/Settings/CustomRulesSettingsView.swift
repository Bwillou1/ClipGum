import AppKit
import ClipGumCore
import SwiftUI

@MainActor
struct CustomRulesSettingsView: View {
    @ObservedObject var model: CustomRulesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Custom Rules & Scripts")
                .font(.title2.bold())
            Text("Rules are stored locally and run only after an explicit test or transformation. JavaScript receives one string and returns one string; it has no ClipGum, file, network, environment, or pasteboard bridge.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !model.policy.scriptsAllowed {
                Label("Custom JavaScript is disabled by a managed profile. Regex rules remain available.", systemImage: "lock.shield.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Saved rules").font(.headline)
                    List(selection: $model.selectedRuleID) {
                        ForEach(model.rules) { rule in
                            HStack {
                                Image(systemName: rule.kind == .script ? "chevron.left.slash.chevron.right" : "textformat")
                                Text(rule.name).lineLimit(1)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { rule.isEnabled },
                                    set: { model.toggle(rule, enabled: $0) }
                                ))
                                .labelsHidden()
                                .disabled(rule.kind == .script && !model.policy.scriptsAllowed)
                            }
                            .tag(Optional(rule.id))
                        }
                    }
                    .frame(minWidth: 220, minHeight: 210)
                    HStack {
                        Button("Delete", role: .destructive) {
                            if let rule = model.selectedRule { model.delete(rule) }
                        }
                        .disabled(model.selectedRule == nil)
                        Spacer()
                        Button("Import JSON") { importPack() }
                        Button("Export JSON") { exportPack() }
                            .disabled(model.rules.isEmpty)
                    }
                    HStack {
                        Button("Import .clipgum") { importBackup() }
                        Button("Export .clipgum") { exportBackup() }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("New rule").font(.headline)
                    TextField("Name", text: $model.draftName)
                    Picker("Kind", selection: $model.draftKind) {
                        Text("Regular expression").tag(CustomRuleKind.regex)
                        Text("Boop JavaScript").tag(CustomRuleKind.script)
                    }
                    .pickerStyle(.segmented)
                    if model.draftKind == .regex {
                        TextField("Pattern", text: $model.draftSource)
                        TextField("Replacement (optional $1 groups)", text: $model.draftReplacement)
                    } else {
                        TextEditor(text: $model.draftSource)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 100)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                        Text("Example: function main(input) { return input.trim(); }")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button("Add Rule") { model.addRule() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.draftKind == .script && !model.policy.scriptsAllowed)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            Text("Interactive playground").font(.headline)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading) {
                    Text("Input").font(.caption)
                    TextEditor(text: $model.playgroundInput)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 90)
                }
                VStack(alignment: .leading) {
                    Text("Output").font(.caption)
                    TextEditor(text: .constant(model.playgroundOutput))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 90)
                        .disabled(true)
                }
            }
            HStack {
                Button(model.isTesting ? "Testing…" : "Test Selected Rule") { model.testSelected() }
                    .disabled(model.isTesting || model.selectedRule == nil)
                Text("250 ms CPU cutoff · 16 MB budget · 2 MiB input/output")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .onAppear { model.policy.refresh() }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = [LocalBackupArchive.fileExtension]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import Encrypted Backup"
        guard panel.runModal() == .OK, let url = panel.url,
              let password = passwordPrompt(confirm: false) else { return }
        model.importBackup(from: url, password: password)
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedFileTypes = [LocalBackupArchive.fileExtension]
        panel.nameFieldStringValue = "ClipGumConfiguration.clipgum"
        panel.prompt = "Export Encrypted Backup"
        guard panel.runModal() == .OK, let url = panel.url,
              let password = passwordPrompt(confirm: true) else { return }
        model.exportBackup(to: url, password: password)
    }

    private func passwordPrompt(confirm: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = confirm ? "Protect this local backup" : "Unlock local backup"
        alert.informativeText = confirm
            ? "Use at least 8 UTF-8 bytes. The password is used only for this explicit export and is not saved."
            : "The password is used only for this explicit import and is not saved."
        alert.addButton(withTitle: confirm ? "Export" : "Import")
        alert.addButton(withTitle: "Cancel")
        let password = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        password.placeholderString = "Backup password"
        if confirm {
            let confirmation = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            confirmation.placeholderString = "Confirm password"
            let stack = NSStackView(views: [password, confirmation])
            stack.orientation = .vertical
            stack.spacing = 8
            alert.accessoryView = stack
            guard alert.runModal() == .alertFirstButtonReturn,
                  password.stringValue == confirmation.stringValue else { return nil }
        } else {
            alert.accessoryView = password
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        }
        return password.stringValue
    }

    private func importPack() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import Rule Pack"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importPack(from: url)
    }

    private func exportPack() {
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["json"]
        panel.nameFieldStringValue = "ClipGumRules.json"
        panel.prompt = "Export Rule Pack"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.exportPack(to: url)
    }
}
