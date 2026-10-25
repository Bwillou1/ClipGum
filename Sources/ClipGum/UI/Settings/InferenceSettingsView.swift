import AppKit
import SwiftUI

@MainActor
struct InferenceSettingsView: View {
    @ObservedObject var preferences: InferencePreferences
    @State private var copyConfirmation: String?

    var body: some View {
        Form {
            Section("Default Model (MLX Apple Silicon)") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.pink)
                        Text("Bonsai Image Ternary 4B MLX")
                            .font(.headline)
                        Spacer()
                        Text("2-bit Ternary")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.pink.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Text("prism-ml/bonsai-image-ternary-4B-mlx-2bit")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospaced()

                    HStack(spacing: 12) {
                        Button {
                            preferences.onLoadModel?("hf:\(ModelIdentifier.defaultHuggingFaceRepo)")
                        } label: {
                            Label("Load Default Model", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            copyBonsaiCliCommands()
                        } label: {
                            Label(copyConfirmation ?? "Copy CLI Download Commands", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Hugging Face Model") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter a Hugging Face repo ID or paste the full model page link:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("e.g. prism-ml/bonsai-image-ternary-4B-mlx-2bit", text: $preferences.huggingFaceRepo)
                            .textFieldStyle(.roundedBorder)
                        Button("Load from HF") {
                            preferences.onLoadModel?(ModelIdentifier.hf(repoOrURL: preferences.huggingFaceRepo))
                        }
                        .buttonStyle(.bordered)
                        .disabled(preferences.huggingFaceRepo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            Section("Localhost / OpenAI-Compatible API (Ollama, LM Studio, etc.)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect to a local server (Ollama, LM Studio, vLLM) or remote endpoint:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LabeledContent("Endpoint") {
                        TextField("http://localhost:11434/v1", text: $preferences.apiEndpoint)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Model Name") {
                        TextField("e.g. llama3, mistral", text: $preferences.apiModelName)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("API Key (Optional)") {
                        SecureField("sk-… (leave empty for local Ollama/LM Studio)", text: $preferences.apiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Spacer()
                        Button {
                            preferences.onLoadModel?(
                                ModelIdentifier.api(
                                    endpoint: preferences.apiEndpoint,
                                    model: preferences.apiModelName,
                                    key: preferences.apiKey
                                )
                            )
                        } label: {
                            Label("Connect to API", systemImage: "network")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            Section("Generation Parameters") {
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

            Section("Privacy and architecture") {
                Text("MLX and GGUF inference run 100% locally on your Mac. Localhost endpoints route only to your designated server. Clipboard text is never sent anywhere else or saved in preferences.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(18)
    }

    private func copyBonsaiCliCommands() {
        let commands = """
        # Install git-xet and clone Bonsai MLX model
        brew install git-xet
        git xet install
        git clone https://huggingface.co/prism-ml/bonsai-image-ternary-4B-mlx-2bit

        # Alternative: using Hugging Face CLI
        curl -LsSf https://hf.co/cli/install.sh | bash
        hf download prism-ml/bonsai-image-ternary-4B-mlx-2bit
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commands, forType: .string)
        copyConfirmation = "Copied!"
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copyConfirmation = nil
        }
    }
}
