import SwiftUI

@MainActor
struct InferenceSettingsView: View {
    @ObservedObject var preferences: InferencePreferences

    var body: some View {
        Form {
            Section("Local inference") {
                LabeledContent("Temperature") {
                    HStack {
                        Slider(value: $preferences.temperature, in: 0.1...0.3, step: 0.05)
                        Text(String(format: "%.2f", preferences.temperature))
                            .monospacedDigit()
                            .frame(width: 36)
                    }
                }
                Stepper(
                    "Output token cap: \(preferences.maximumOutputTokens)",
                    value: $preferences.maximumOutputTokens,
                    in: 64...512,
                    step: 64
                )
                Picker("Unload after idle", selection: $preferences.idleUnloadMinutes) {
                    Text("1 minute").tag(1.0)
                    Text("5 minutes").tag(5.0)
                    Text("15 minutes").tag(15.0)
                    Text("30 minutes").tag(30.0)
                    Text("60 minutes").tag(60.0)
                }
            }

            Section("Privacy and model loading") {
                Text("Choose an MLX model folder or GGUF file from the ClipGum menu, or use the first-run verified-model downloader. Inference is local-only; model downloads occur only after explicit selection and verification metadata review.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Changing these settings does not read the clipboard. Clipboard text is never saved in preferences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(18)
    }
}
