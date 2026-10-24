import SwiftUI

@MainActor
struct PublicBetaSettingsView: View {
    @ObservedObject var inference: InferencePreferences
    @ObservedObject var updates: UpdateManager
    @ObservedObject var diagnostics: DiagnosticsEngine
    let onCopyDiagnostics: (String) -> Bool
    let onClearAllData: () -> Void
    let onReplayOnboarding: () -> Void

    var body: some View {
        TabView {
            InferenceSettingsView(preferences: inference)
                .tabItem { Label("Inference", systemImage: "cpu") }
            UpdateSettingsView(manager: updates)
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            PrivacyAuditView(
                diagnostics: diagnostics,
                onCopyPayload: onCopyDiagnostics,
                onClearAllData: onClearAllData,
                onReplayOnboarding: onReplayOnboarding
            )
            .tabItem { Label("Privacy & Audit", systemImage: "hand.raised.shield") }
            LicensesView()
                .tabItem { Label("Licenses", systemImage: "doc.text.magnifyingglass") }
        }
        .frame(width: 780, height: 610)
    }
}
