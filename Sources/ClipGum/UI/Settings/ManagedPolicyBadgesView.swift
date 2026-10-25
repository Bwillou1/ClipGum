import ClipGumCore
import SwiftUI

@MainActor
struct ManagedPolicyBadgesView: View {
    @ObservedObject var policy: EnterprisePolicyController

    var body: some View {
        if !policy.badges.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.orange)
                ForEach(policy.badges, id: \.self) { badge in
                    Label(badge, systemImage: "lock.fill")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.13))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .accessibilityLabel("Managed enterprise policy active")
        }
    }
}

@MainActor
struct EnterprisePolicySettingsView: View {
    @ObservedObject var policy: EnterprisePolicyController

    var body: some View {
        Form {
            Section("Managed deployment") {
                Text("ClipGum reads managed preferences through CFPreferences without writing to the managed domain. Values below are effective only when your administrator supplies them in a configuration profile.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                policyRow(.disableExternalLLM, title: "DisableExternalLLM", detail: "Local on-device inference only; ClipGum has no external inference backend.")
                policyRow(.forceSecretRedaction, title: "ForceSecretRedaction", detail: "Strict deterministic redaction is applied again immediately before every copy/paste write. Rich payloads become redacted plain text.")
                policyRow(.disableCustomScripts, title: "DisableCustomScripts", detail: "JavaScript rules cannot be added, enabled, or tested. Regex rules remain available.")
                policyRow(.lockTelemetry, title: "LockTelemetry", detail: "Diagnostics are forced off and the opt-in control is locked.")
            }
            Section("Zero-idle policy reads") {
                Text("Policy values are read on launch, when Settings appears, and at explicit action boundaries. No managed-preference watcher, polling timer, or background refresh is installed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Refresh Policy Now") { policy.refresh() }
            }
        }
        .formStyle(.grouped)
        .padding(18)
        .onAppear { policy.refresh() }
    }

    private func policyRow(_ key: ManagedPolicyKey, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if policy.snapshot.isForced(key) {
                    Label(policy.snapshot.value(key) ? "Managed ON" : "Managed OFF", systemImage: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                } else {
                    Text(policy.snapshot.value(key) ? "On" : "Off")
                        .foregroundStyle(.secondary)
                }
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}
