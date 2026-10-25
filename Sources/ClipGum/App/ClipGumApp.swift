import SwiftUI

@main
@MainActor
struct ClipGumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // AppDelegate owns the real NSStatusItem. This empty Settings scene
        // keeps the app scene-based without creating a second menu bar item.
        Settings {
            PublicBetaSettingsView(
                inference: appDelegate.inferencePreferences,
                updates: appDelegate.updateManager,
                diagnostics: appDelegate.diagnostics,
                policy: appDelegate.enterprisePolicy,
                rules: appDelegate.customRules,
                onCopyDiagnostics: { [weak appDelegate] text in
                    appDelegate?.copyDiagnosticsPayload(text) ?? false
                },
                onClearAllData: { [weak appDelegate] in
                    appDelegate?.clearAllData()
                },
                onReplayOnboarding: { [weak appDelegate] in
                    appDelegate?.replayOnboarding()
                }
            )
            .onOpenURL { url in
                appDelegate.handleDeepLink(url)
            }
        }
    }
}
