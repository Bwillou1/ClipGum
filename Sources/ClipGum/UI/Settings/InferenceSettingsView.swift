import AppKit
import SwiftUI

@MainActor
struct InferenceSettingsView: View {
    @ObservedObject var preferences: InferencePreferences
    @ObservedObject var bonsaiManager = BonsaiModelManager.shared
    @State private var copyConfirmation: String?
    @State private var showLicenseDetails: Bool = false
    @State private var clipboardIntent: IntentPrediction = IntentPrediction(
        category: .generalClean,
        probability: 0.72,
        confidenceText: "Standard (72%)",
        diagnosis: "Analyse en attente...",
        suggestedActionName: "Nettoyer",
        isHighConfidence: false
    )

    var body: some View {
        Form {
            // MARK: - Bonsai 4B 1-Click & License Section
            Section("Modèle par Défaut (Bonsai 4B MLX - Apple Silicon)") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.pink)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Bonsai Image Ternary 4B MLX")
                                .font(.headline)
                            Text("prism-ml/bonsai-image-ternary-4B-mlx-2bit")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospaced()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("2-bit Ternaire")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.pink.opacity(0.15))
                                .foregroundStyle(.pink)
                                .clipShape(Capsule())
                            Text("Licence Apache 2.0")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // License & Terms Acceptance
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Toggle(isOn: $bonsaiManager.isLicenseAccepted) {
                                Text("J'accepte la licence Apache 2.0 et les conditions d'utilisation de Bonsai 4B (Prism ML)")
                                    .font(.subheadline)
                            }
                            .toggleStyle(.checkbox)

                            Spacer()

                            Button {
                                showLicenseDetails.toggle()
                            } label: {
                                Text(showLicenseDetails ? "Masquer la licence" : "Lire la licence...")
                                    .font(.caption)
                                    .underline()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        }

                        if showLicenseDetails {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Conditions d'utilisation Bonsai 4B (Prism ML, Inc.)")
                                    .font(.caption.bold())
                                Text("• Ce logiciel et ses poids sont sous licence Apache 2.0 (Copyright 2026 Prism ML, Inc.).\n• Basé sur FLUX.2 Klein 4B & Qwen3-4B sous licence Apache 2.0.\n• Inférence 100% locale sur votre Mac Apple Silicon (Metal/MLX) sans télémétrie ni envoi de données.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    // 1-Click Download or Load Button
                    HStack(spacing: 12) {
                        if bonsaiManager.isDownloading {
                            VStack(alignment: .leading, spacing: 4) {
                                ProgressView(value: bonsaiManager.progress)
                                    .progressViewStyle(.linear)
                                HStack {
                                    Text(bonsaiManager.statusMessage)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Annuler") {
                                        bonsaiManager.cancelDownload()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        } else if bonsaiManager.isDownloaded {
                            Button {
                                preferences.onLoadModel?("mlx:\(bonsaiManager.modelDirectory.path)")
                            } label: {
                                Label("Charger Bonsai 4B Local (Prêt)", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)

                            Text("Installé localement")
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Button {
                                bonsaiManager.startOneClickDownload {
                                    preferences.onLoadModel?("mlx:\(bonsaiManager.modelDirectory.path)")
                                }
                            } label: {
                                Label("Télécharger Bonsai 4B en 1-Clic", systemImage: "arrow.down.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.pink)
                            .disabled(!bonsaiManager.isLicenseAccepted)

                            Button {
                                copyBonsaiCliCommands()
                            } label: {
                                Label(copyConfirmation ?? "Copier Commandes CLI", systemImage: "terminal")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    Text(bonsaiManager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            // MARK: - Smart Intent & Probability of Need Section
            Section("🎯 Analyse d'Intention & Probabilité du Besoin (Presse-papiers)") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(clipboardIntent.category.rawValue)
                                .font(.headline)
                            Text(clipboardIntent.diagnosis)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Probabilité du Besoin")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(clipboardIntent.percentageString)
                                .font(.title3.bold())
                                .foregroundStyle(clipboardIntent.probability > 0.85 ? .green : .blue)
                        }
                    }

                    HStack {
                        Text("Action Recommandée :")
                            .font(.caption.bold())
                        Text(clipboardIntent.suggestedActionName)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Capsule())
                        Spacer()
                        Button("Rafraîchir l'analyse") {
                            refreshIntentPrediction()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
                .onAppear {
                    refreshIntentPrediction()
                }
            }

            // MARK: - Custom Hugging Face Model
            Section("Modèle Hugging Face Personnalisé") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Collez un identifiant de dépôt ou un lien Hugging Face complet :")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("ex: prism-ml/bonsai-image-ternary-4B-mlx-2bit", text: $preferences.huggingFaceRepo)
                            .textFieldStyle(.roundedBorder)
                        Button("Charger depuis HF") {
                            preferences.onLoadModel?(ModelIdentifier.hf(repoOrURL: preferences.huggingFaceRepo))
                        }
                        .buttonStyle(.bordered)
                        .disabled(preferences.huggingFaceRepo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            // MARK: - Localhost / API
            Section("Serveur Local / API Compatible OpenAI (Ollama, LM Studio)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connectez ClipGum à Ollama, LM Studio ou vLLM sur votre machine :")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LabeledContent("Endpoint") {
                        TextField("http://localhost:11434/v1", text: $preferences.apiEndpoint)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Nom du Modèle") {
                        TextField("ex: llama3, mistral, qwen", text: $preferences.apiModelName)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Clé API (Optionnelle)") {
                        SecureField("sk-… (laisser vide pour Ollama / LM Studio)", text: $preferences.apiKey)
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
                            Label("Connecter à l'API", systemImage: "network")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            // MARK: - Generation Parameters
            Section("Paramètres de Génération") {
                LabeledContent("Température") {
                    HStack {
                        Slider(value: $preferences.temperature, in: 0.1...0.3, step: 0.05)
                        Text(String(format: "%.2f", preferences.temperature))
                            .monospacedDigit()
                            .frame(width: 36)
                    }
                }
                Stepper(
                    "Plafond de tokens en sortie : \(preferences.maximumOutputTokens)",
                    value: $preferences.maximumOutputTokens,
                    in: 64...512,
                    step: 64
                )
                Picker("Décharger de la mémoire après inactivité", selection: $preferences.idleUnloadMinutes) {
                    Text("1 minute").tag(1.0)
                    Text("5 minutes").tag(5.0)
                    Text("15 minutes").tag(15.0)
                    Text("30 minutes").tag(30.0)
                    Text("60 minutes").tag(60.0)
                }
            }

            Section("Confidentialité et Architecture") {
                Text("L'inférence MLX et GGUF s'exécute à 100% localement sur votre Mac. Les serveurs localhost ne communiquent qu'avec votre machine. Le texte du presse-papiers n'est jamais stocké ni transmis à des tiers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(18)
    }

    private func refreshIntentPrediction() {
        if let currentText = NSPasteboard.general.string(forType: .string) {
            clipboardIntent = IntentProbabilityEngine.shared.predict(for: currentText)
        }
    }

    private func copyBonsaiCliCommands() {
        let commands = """
        # Installer git-xet et cloner Bonsai MLX
        brew install git-xet
        git xet install
        git clone https://huggingface.co/prism-ml/bonsai-image-ternary-4B-mlx-2bit

        # Alternative avec Hugging Face CLI
        curl -LsSf https://hf.co/cli/install.sh | bash
        hf download prism-ml/bonsai-image-ternary-4B-mlx-2bit
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commands, forType: .string)
        copyConfirmation = "Copié !"
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copyConfirmation = nil
        }
    }
}
