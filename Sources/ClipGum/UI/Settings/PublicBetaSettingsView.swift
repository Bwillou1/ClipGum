import SwiftUI

@MainActor
struct PublicBetaSettingsView: View {
    @ObservedObject var inference: InferencePreferences
    @ObservedObject var updates: UpdateManager
    @ObservedObject var diagnostics: DiagnosticsEngine
    @ObservedObject var policy: EnterprisePolicyController
    @ObservedObject var rules: CustomRulesViewModel
    let onCopyDiagnostics: (String) -> Bool
    let onClearAllData: () -> Void
    let onReplayOnboarding: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ManagedPolicyBadgesView(policy: policy)
            TabView {
                InferenceSettingsView(preferences: inference)
                    .tabItem { Label("Inference", systemImage: "cpu") }
                CustomRulesSettingsView(model: rules)
                    .tabItem { Label("Rules", systemImage: "chevron.left.slash.chevron.right") }
                UpdateSettingsView(manager: updates)
                    .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
                PrivacyAuditView(
                    diagnostics: diagnostics,
                    onCopyPayload: onCopyDiagnostics,
                    onClearAllData: onClearAllData,
                    onReplayOnboarding: onReplayOnboarding
                )
                .tabItem { Label("Privacy & Audit", systemImage: "hand.raised.shield") }
                EnterprisePolicySettingsView(policy: policy)
                    .tabItem { Label("Enterprise", systemImage: "building.2") }
                LicensesView()
                    .tabItem { Label("Licenses", systemImage: "doc.text.magnifyingglass") }
            }
        }
        .frame(width: 860, height: 680)
        .onAppear {
            policy.refresh()
            diagnostics.applyPolicy(lockTelemetry: policy.telemetryLocked)
        }
    }
}
