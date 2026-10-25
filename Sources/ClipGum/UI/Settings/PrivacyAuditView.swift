import SwiftUI

@MainActor
struct PrivacyAuditView: View {
    @ObservedObject var diagnostics: DiagnosticsEngine
    let onCopyPayload: (String) -> Bool
    let onClearAllData: () -> Void
    let onReplayOnboarding: () -> Void

    @State private var payloadText = ""
    @State private var copyConfirmed = false

    var body: some View {
        Form {
            Section("Content firewall") {
                Text("Clipboard text, transformed output, regex tokens, and Share-Ready/session mappings are never accepted by this diagnostics API. ClipGum registers no crash reporter, content logger, analytics SDK, or telemetry endpoint.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Collect non-content diagnostics on this Mac", isOn: Binding(
                    get: { diagnostics.isEnabled },
                    set: { diagnostics.setEnabled($0) }
                ))
                .disabled(diagnostics.isTelemetryLocked)
                if diagnostics.isTelemetryLocked {
                    Label("Telemetry is locked off by the managed enterprise policy.", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Text("Off by default. Disabling also clears collected values. Data stays in volatile memory and is never transmitted automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Exact payload — inspect before explicit export") {
                ScrollView {
                    Text(payloadText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 210, maxHeight: 280)
                HStack {
                    Button(copyConfirmed ? "Copied Exact JSON" : "Copy Exact JSON") {
                        copyConfirmed = onCopyPayload(payloadText)
                    }
                    .disabled(payloadText.isEmpty)
                    Button("Refresh") { refreshPayload() }
                    Spacer()
                    Text("Copying is a deliberate pasteboard write; there is no Send button or network upload.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Data controls") {
                Button("Clear All Data", role: .destructive) {
                    onClearAllData()
                    refreshPayload()
                }
                Text("Clears all diagnostic counters/latencies/errors/peak RAM and withdraws diagnostics opt-in. The same action clears volatile preview, Chain Copy, and Share-Ready mappings. Downloaded model files and ordinary preferences are not deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Replay First-Run Walkthrough") { onReplayOnboarding() }
            }
        }
        .formStyle(.grouped)
        .padding(18)
        .onAppear { refreshPayload() }
        .onChange(of: diagnostics.snapshot) { _ in refreshPayload() }
        .onChange(of: diagnostics.isEnabled) { _ in refreshPayload() }
    }

    private func refreshPayload() {
        payloadText = (try? diagnostics.payloadText()) ?? ""
        copyConfirmed = false
    }
}
