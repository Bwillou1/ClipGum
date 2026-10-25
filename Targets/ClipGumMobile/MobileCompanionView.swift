import ClipGumCore
import SwiftUI
import UniformTypeIdentifiers

@available(iOS 17.0, *)
struct MobileCompanionView: View {
    private let cleaner = MobileCleaningService()
    private let inference = MobileInferenceCoordinator()
    @State private var input = ""
    @State private var output = ""
    @State private var status = "Enter or share text explicitly. This screen never reads the clipboard."
    @State private var model: CoreMLTextInference?
    @State private var showModelPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label("On-device · No cloud processing", systemImage: "lock.shield.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text(status).font(.caption).foregroundStyle(.secondary)
                    NavigationLink("Local Handoff / Receive") {
                        MobileHandoffView(initialText: "")
                    }
                    TextEditor(text: $input)
                        .frame(minHeight: 150)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                        .accessibilityLabel("Text to clean")
                    HStack {
                        Button("Clean") { clean() }
                        Button("Scrub secrets") {
                            output = cleaner.scrubSecrets(input).output
                            status = "Secrets scrubbed deterministically."
                        }
                        Button("Strip URLs") {
                            output = cleaner.stripURLTracking(input).output
                            status = "Tracking URL parameters removed deterministically."
                        }
                    }
                    HStack {
                        Button("Extract table") {
                            do {
                                output = try cleaner.extractTable(input)
                                status = "Table normalized locally."
                            } catch {
                                status = "The table is malformed; no output was exported."
                            }
                        }
                        Button("Local CoreML") { showModelPicker = true }
                        Button("Run on-device") { runModel() }
                            .disabled(model == nil)
                    }
                    if !output.isEmpty {
                        Text("Preview").font(.headline)
                        TextEditor(text: .constant(output))
                            .frame(minHeight: 150)
                            .disabled(true)
                        HStack {
                            ShareLink(item: output) {
                                Label("Share cleaned text", systemImage: "square.and.arrow.up")
                            }
                            NavigationLink("Send to device") {
                                MobileHandoffView(initialText: output)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("ClipGum")
            .fileImporter(
                isPresented: $showModelPicker,
                allowedContentTypes: [UTType(filenameExtension: "mlmodelc") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    do {
                        model = try CoreMLTextInference(modelURL: url)
                        status = "Local compiled CoreML model selected. No weights were downloaded."
                    } catch {
                        status = "The local model could not be loaded within the mobile budget."
                    }
                case .failure:
                    status = "No local model was selected."
                }
            }
        }
    }

    private func clean() {
        output = cleaner.clean(input).output
        status = "Text cleaned deterministically on-device."
    }

    private func runModel() {
        let source = input
        status = "Running the selected local model; deterministic fallback remains available."
        Task {
            do {
                let transformed = try await inference.transform(source, using: model)
                await MainActor.run {
                    output = transformed
                    status = "Local processing finished with deterministic cleaning; fallback is used when needed."
                }
            } catch {
                await MainActor.run {
                    output = ""
                    status = "The input exceeds the bounded mobile inference profile. Deterministic actions remain available."
                }
            }
        }
    }
}
