import SwiftUI

@MainActor
struct OnboardingView: View {
    @ObservedObject var controller: OnboardingController
    @ObservedObject var diagnostics: DiagnosticsEngine
    @ObservedObject var downloadController: ModelDownloadController
    let onChooseModel: (InferenceBackendKind) -> Void
    let onLoadVerifiedModel: (VerifiedModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.title)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Welcome to ClipGum").font(.title2.bold())
                    Text(controller.progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("Offline / Local Only", systemImage: "checkmark.shield.fill")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.16))
                    .clipShape(Capsule())
            }

            Divider()
            Group {
                switch controller.step {
                case .explicitTrigger: triggerStep
                case .permissions: permissionsStep
                case .modelReadiness: modelStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            HStack {
                Button("Back") { controller.goBack() }
                    .disabled(controller.step == .explicitTrigger)
                Spacer()
                if controller.isLastStep {
                    Button("Finish") { controller.finish() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Continue") { controller.advance() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 720, height: 570)
        .onAppear { controller.refreshAccessibility() }
    }

    private var triggerStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                onboardingSection(
                    "One explicit shortcut",
                    "Copy text in another app, then press ⌘⇧V. ClipGum reads the general pasteboard only after that invocation (or the equivalent menu-bar action). There is no polling, watcher, history, background rewrite, or app-profile-triggered clipboard read."
                )
                onboardingSection(
                    "Nothing changes until you choose",
                    "Review Before / After output first. Copy Result, Paste Cleaned, Paste Original, and Chain Copy are separate explicit actions. The original text stays recoverable in volatile preview memory until dismissal."
                )
                onboardingSection(
                    "Sensitive values fail closed",
                    "Concealed, transient, auto-generated, and known password-manager markers are checked before every content-flavor read. Excluded items are skipped without reading their text."
                )
                VStack(alignment: .leading, spacing: 8) {
                    Text("Optional non-content diagnostics").font(.headline)
                    Text("Off by default. If you opt in, ClipGum counts feature activations, execution latency, peak RAM, and fixed error codes only. No telemetry is transmitted; Privacy & Audit shows the exact JSON you may explicitly copy.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Toggle("Enable non-content diagnostics", isOn: Binding(
                        get: { diagnostics.isEnabled },
                        set: { diagnostics.setEnabled($0) }
                    ))
                }
            }
        }
    }

    private var permissionsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                onboardingSection(
                    "Accessibility — only for Paste Cleaned",
                    "ClipGum requests Accessibility only when you explicitly ask to synthesize ⌘V. Copy Result never requires it. Denial leaves the existing pasteboard unchanged."
                )
                Label(
                    controller.accessibilityGranted ? "Accessibility granted" : "Accessibility not granted",
                    systemImage: controller.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .foregroundStyle(controller.accessibilityGranted ? Color.green : Color.orange)
                HStack {
                    Button("Enable & Check Accessibility") { controller.requestAccessibility() }
                    Button("Open Accessibility Settings") {
                        SystemPermissionCenter.openAccessibilitySettings()
                    }
                    Button("Check Again") { controller.refreshAccessibility() }
                }
                Text(PermissionRecoveryGuide.accessibility(
                    isTrusted: controller.accessibilityGranted
                ).recoverySteps.joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()
                onboardingSection(
                    "Input Monitoring — guidance without a blanket prompt",
                    "ClipGum registers a ⌘⇧V hotkey and does not run a global input-monitoring event tap. Input Monitoring is not requested by default. If macOS specifically requires it for your configuration, open the settings below, then return and retry the shortcut."
                )
                Button("Open Input Monitoring Settings") {
                    SystemPermissionCenter.openInputMonitoringSettings()
                }
                onboardingSection(
                    "Pasteboard permission recovery",
                    "If macOS denies Paste from Other Apps, ClipGum shows a recovery panel and does not read content. Allow ClipGum under Privacy & Security → Paste from Other Apps, then invoke ⌘⇧V again."
                )
                Button("Open Pasteboard Privacy Settings") {
                    SystemPermissionCenter.openPasteboardSettings()
                }
            }
        }
    }

    private var modelStep: some View {
        let readiness = ModelReadiness.current(
            requiredRAMBytes: downloadController.manifest?.minimumUnifiedRAMBytes ?? 0
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                onboardingSection(
                    "Apple Silicon and unified-memory readiness",
                    readiness.summary
                )
                Text("Inference runs on this Mac. The Offline / Local Only badge describes inference; only an explicit update check or model download uses the network.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Choose Local MLX Folder…") { onChooseModel(.mlx) }
                    Button("Choose Local GGUF File…") { onChooseModel(.gguf) }
                }

                Divider()
                Text("Verified local model-weight download").font(.headline)
                Text("Select a local JSON manifest first. ClipGum validates every filename, HTTPS URL, byte count, and SHA-256, downloads to staging, then installs atomically. No default publisher or unverified hash is hard-coded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let manifest = downloadController.manifest {
                    Label("\(manifest.displayName) · \(manifest.backend.rawValue.uppercased()) · \(manifest.files.count) file(s)", systemImage: "doc.badge.checkmark")
                }
                HStack {
                    Button("Select Model Manifest…") { downloadController.chooseManifest() }
                        .disabled(downloadController.isDownloading)
                    Button("Download & Verify") {
                        Task { await downloadController.downloadAndVerify() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        downloadController.manifest == nil
                            || downloadController.isDownloading
                            || !readiness.canLoadModel
                    )
                }
                if downloadController.isDownloading { ProgressView().controlSize(.small) }
                Text(downloadController.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let verified = downloadController.verifiedModel {
                    Button("Load Verified \(verified.manifest.backend.rawValue.uppercased()) Model") {
                        onLoadVerifiedModel(verified)
                    }
                }
            }
        }
    }

    private func onboardingSection(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
