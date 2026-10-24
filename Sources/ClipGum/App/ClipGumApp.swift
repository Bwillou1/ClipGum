import SwiftUI

@main
@MainActor
struct ClipGumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // AppDelegate owns the real NSStatusItem. This empty Settings scene
        // keeps the app scene-based without creating a second menu bar item.
        Settings {
            InferenceSettingsView(preferences: appDelegate.inferencePreferences)
        }
    }
}
