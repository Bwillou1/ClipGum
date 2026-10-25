import AppKit
import ClipGumCore
import Foundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let cleaner = RuleCleaningService()
    private let richTextSanitizer = RichTextSanitizer()
    private let pasteboard = SystemPasteboard()
    private let shareReadySession: ShareReadySession
    private let paletteController = PalettePanelController()
    private var chainSession = ChainCopySession()
    private lazy var pasteService = PasteService(
        pasteboard: pasteboard,
        requiresSecretRedaction: { [weak self] in
            self?.enterprisePolicy.requiresRedactionNow ?? false
        }
    )

    let inferencePreferences: InferencePreferences
    let updateManager: UpdateManager
    let diagnostics: DiagnosticsEngine
    let enterprisePolicy: EnterprisePolicyController
    let customRules: CustomRulesViewModel
    private let inferenceEngine: LocalInferenceEngine
    private var quickActionServices: QuickActionServicesProvider?
    private let pipeline: SmartPastePipeline
    private let modelDownloadController: ModelDownloadController

    private var menuBarController: MenuBarController?
    private var onboardingController: OnboardingController?
    private var onboardingWindow: NSWindow?
    private var hotKey: GlobalHotKey?
    private var paletteModel: PaletteModel?
    private var currentPreview: PalettePreview?
    private var currentDocument: PasteboardDocument?
    private var targetApplication: NSRunningApplication?
    private var inferenceTask: Task<Void, Never>?
    private var modelLoadTask: Task<Void, Never>?
    private var activeGenerationID: UUID?
    private var selectedModelIdentifier: String?
    private var modelAccess: SecurityScopedModelAccess?
    private let p2pHandoff: P2PHandoffController
    private var p2pWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var inspectorWindow: NSWindow?

    override init() {
        let preferences = InferencePreferences()
        let engine = LocalInferenceEngine(configuration: preferences.configuration)
        let shareReady = ShareReadySession()
        let policy = EnterprisePolicyController()
        inferencePreferences = preferences
        inferenceEngine = engine
        shareReadySession = shareReady
        enterprisePolicy = policy
        customRules = CustomRulesViewModel(policy: policy)
        updateManager = UpdateManager()
        diagnostics = DiagnosticsEngine(telemetryLocked: policy.telemetryLocked)
        modelDownloadController = ModelDownloadController()
        p2pHandoff = P2PHandoffController()
        pipeline = SmartPastePipeline(
            engine: engine,
            shareReadySession: shareReady,
            configuration: preferences.configuration
        )
        super.init()

        p2pHandoff.copyReceivedHandler = { [weak self] text in
            guard let self else { return false }
            do {
                try self.pasteService.copyResult(text)
                return true
            } catch {
                return false
            }
        }
        p2pHandoff.dismissHandler = { [weak self] in
            self?.p2pWindow?.close()
            self?.p2pWindow = nil
        }
        customRules.portableSettingsProvider = { [weak self] in
            guard let self else { return PortableSettings() }
            return PortableSettings(
                temperature: self.inferencePreferences.temperature,
                modelOffloadSeconds: Int((self.inferencePreferences.idleUnloadMinutes * 60).rounded()),
                maximumOutputTokens: self.inferencePreferences.maximumOutputTokens,
                telemetryEnabled: self.diagnostics.isEnabled
            )
        }
        customRules.importSettingsHandler = { [weak self] settings in
            guard let self else { return }
            self.inferencePreferences.temperature = min(0.3, max(0.1, settings.temperature))
            self.inferencePreferences.maximumOutputTokens = min(512, max(64, settings.maximumOutputTokens))
            self.inferencePreferences.idleUnloadMinutes = min(60, max(1, Double(settings.modelOffloadSeconds) / 60))
            self.diagnostics.applyPolicy(lockTelemetry: self.enterprisePolicy.telemetryLocked)
            self.diagnostics.setEnabled(settings.telemetryEnabled)
            // Model paths and mobile-only preferences are deliberately not
            // auto-applied on macOS; no model load is triggered by an import.
        }

        preferences.onChange = { configuration in
            Task {
                await engine.updateConfiguration(configuration)
            }
        }
        preferences.onLoadModel = { [weak self] identifier in
            self?.loadModelByIdentifier(identifier)
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        handleExplicitUserTrigger()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(
            cleanAction: { [weak self] in
                self?.handleExplicitUserTrigger()
            },
            radialAction: { [weak self] in
                self?.handleRadialUserTrigger()
            },
            chooseDefaultAction: { [weak self] in
                self?.loadDefaultModel()
            },
            chooseMLXAction: { [weak self] in
                self?.chooseModel(backend: .mlx)
            },
            chooseGGUFAction: { [weak self] in
                self?.chooseModel(backend: .gguf)
            },
            unloadModelAction: { [weak self] in
                self?.unloadSelectedModel()
            },
            openSettingsAction: { [weak self] in
                self?.openInferenceSettings()
            },
            openInspectorAction: { [weak self] in
                self?.openLiveInspector()
            },
            quitAction: {
                NSApp.terminate(nil)
            }
        )

        // When launched directly from Finder or Spotlight, immediately present the palette
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.handleExplicitUserTrigger()
        }

        Task {
            await inferenceEngine.setStatusHandler { [weak self] status in
                Task { @MainActor in
                    self?.menuBarController?.updateInferenceStatus(status)
                }
            }
        }

        let hotKey = GlobalHotKey(
            standardAction: { [weak self] in
                Task { @MainActor in
                    self?.handleExplicitUserTrigger()
                }
            },
            radialAction: { [weak self] in
                Task { @MainActor in
                    self?.handleRadialUserTrigger()
                }
            }
        )
        self.hotKey = hotKey

        do {
            try hotKey.registerShortcuts()
        } catch {
            presentHotKeyError(error)
        }

        let services = QuickActionServicesProvider()
        quickActionServices = services
        NSApp.servicesProvider = services
        NSApp.registerServicesMenuSendTypes([.string], returnTypes: [.string])
        Task {
            await LocalModelIntentBridge.shared.install { [weak self] input in
                guard let self else { throw LocalModelIntentError.modelUnavailable }
                return try await self.transformForIntent(input)
            }
        }

        updateManager.start()
        presentOnboardingIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        shareReadySession.clear()
        chainSession.clear()
        currentDocument = nil
        currentPreview = nil
        hotKey?.invalidate()
        inferenceTask?.cancel()
        modelLoadTask?.cancel()
        modelAccess = nil
        p2pHandoff.stop()
        p2pWindow?.close()
        p2pWindow = nil
        onboardingWindow?.close()
        onboardingWindow = nil
        onboardingController = nil
    }

    /// The standard entry point that opens the full HUD (⌘⇧V).
    private func handleExplicitUserTrigger() {
        if paletteController.isPresented {
            paletteController.dismiss()
            return
        }
        triggerPaletteCapture(radial: false)
    }

    /// The radial mouse-cursor wheel entry point (⌘⌥V).
    func handleRadialUserTrigger() {
        if paletteController.isPresented {
            paletteController.dismiss()
            return
        }
        triggerPaletteCapture(radial: true)
    }

    private func triggerPaletteCapture(radial: Bool) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        targetApplication = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            ? nil
            : frontmost

        let appProfile = OfficeAppProfileResolver.profile(application: frontmost)
        switch pasteboard.readDocumentForExplicitUserAction() {
        case .document(let document):
            handleCapturedDocument(document, appProfile: appProfile, radial: radial)
        case .text(let original):
            handleCapturedDocument(
                PasteboardDocument(plainText: original),
                appProfile: appProfile,
                radial: radial
            )
        case .accessDenied:
            showPalette(.message(PaletteMessage(
                title: "Pasteboard access is denied",
                detail: "ClipGum did not read the clipboard. Allow ClipGum in System Settings → Privacy & Security → Paste from Other Apps, then invoke ⌘⇧V again.",
                showsPrivacySettings: true
            )), radial: radial)
        case .excluded:
            showPalette(.message(PaletteMessage(
                title: "Sensitive clipboard skipped",
                detail: "The source marked this item as concealed, transient, auto-generated, or a known password-manager value. ClipGum inspected metadata only and did not read its text."
            )), radial: radial)
        case .noText:
            showPalette(.message(PaletteMessage(
                title: "No supported text found",
                detail: "ClipGum handles one plain-text, public.html, or public.rtf item. Copy a single text selection, then invoke ClipGum again.",
                systemImage: "doc.questionmark"
            )), radial: radial)
        case .emptyText:
            showPalette(.message(PaletteMessage(
                title: "Clipboard text is empty",
                detail: "Copy some text, then invoke ClipGum again.",
                systemImage: "doc"
            )), radial: radial)
        case .multipleItems:
            showPalette(.message(PaletteMessage(
                title: "Multiple items not supported",
                detail: "ClipGum intentionally handles one text item at a time. Copy a single text selection and try again.",
                systemImage: "rectangle.stack"
            )), radial: radial)
        }
    }

    private func handleCapturedDocument(
        _ document: PasteboardDocument,
        appProfile: OfficeAppProfile,
        radial: Bool = false
    ) {
        do {
            let original = try richTextSanitizer.plainText(from: document)
            guard !original.isEmpty else {
                showPalette(.message(PaletteMessage(
                    title: "Clipboard text is empty",
                    detail: "The captured flavors contain no visible text. Copy some text, then invoke ClipGum again.",
                    systemImage: "doc"
                )), radial: radial)
                return
            }
            if chainSession.isActive {
                chainSession.add(original)
                currentPreview = nil
                showPalette(.chain(chainSession), radial: radial)
            } else {
                let startTime = CFAbsoluteTimeGetCurrent()
                let cleanResult = cleaner.clean(original)
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
                let preview = PalettePreview(deterministicResult: cleanResult)
                currentPreview = preview

                let secretsCount = cleanResult.matches.filter { $0.rule.category == .secret }.count
                let trackersCount = cleanResult.matches.filter { $0.rule.category == .tracker }.count
                let detectedType = original.hasPrefix("http://") || original.hasPrefix("https://") ? "URL Traquée" :
                                   original.contains("{") && original.contains("}") ? "JSON" :
                                   original.contains("\t") || original.contains("|") ? "Tableau" :
                                   secretsCount > 0 ? "Secrets / Clés" : "Texte Brut"

                LiveInspectorEngine.shared.record(
                    trigger: radial ? "⌘⌥V Roue Radiale" : "⌘⇧V Raccourci",
                    contentType: detectedType,
                    original: original,
                    cleaned: cleanResult.cleanedText,
                    trackersRemoved: trackersCount,
                    secretsRedacted: secretsCount,
                    latencyMs: elapsedMs,
                    actionName: "Règles Déterministes"
                )

                showPalette(.preview(preview), document: document, appProfile: appProfile, radial: radial)
            }
        } catch {
            showPalette(.message(PaletteMessage(
                title: "Rich text could not be read",
                detail: userFacingMessage(for: error),
                systemImage: "doc.questionmark"
            )), radial: radial)
        }
    }

    private func showPalette(
        _ content: PaletteContent,
        document: PasteboardDocument? = nil,
        appProfile: OfficeAppProfile? = nil,
        radial: Bool = false
    ) {
        currentDocument = document
        switch content {
        case .message, .chain:
            currentPreview = nil
        case .preview:
            break
        }

        enterprisePolicy.refresh()
        diagnostics.applyPolicy(lockTelemetry: enterprisePolicy.telemetryLocked)
        let model = PaletteModel(
            content: content,
            document: document,
            appProfile: appProfile
        )
        model.managedPolicyBadges = enterprisePolicy.badges
        model.shareReadyMappingCount = shareReadySession.mappingCount
        paletteModel = model

        if radial {
            paletteController.showRadial(
                model: model,
                onAction: { [weak self] action in
                    self?.handlePaletteAction(action)
                },
                onDismiss: { [weak self] in
                    self?.inferenceTask?.cancel()
                    self?.inferenceTask = nil
                    self?.activeGenerationID = nil
                    self?.currentPreview = nil
                    self?.currentDocument = nil
                    self?.paletteModel = nil
                    self?.targetApplication = nil
                }
            )
        } else {
            paletteController.show(
                model: model,
                onAction: { [weak self] action in
                    self?.handlePaletteAction(action)
                },
                onDismiss: { [weak self] in
                    self?.inferenceTask?.cancel()
                    self?.inferenceTask = nil
                    self?.activeGenerationID = nil
                    self?.currentPreview = nil
                    self?.currentDocument = nil
                    self?.paletteModel = nil
                    self?.targetApplication = nil
                }
            )
        }
    }

    private func handlePaletteAction(_ action: PaletteAction) {
        switch action {
        case .cancel:
            paletteController.dismiss()
        case .openPasteboardPrivacySettings:
            paletteController.dismiss()
            openSystemSettings(anchor: "Privacy_Pasteboard")
        case .runTransformation(let action):
            runTransformation(action)
        case .restoreDeterministic:
            restoreDeterministic(message: nil)
        case .clearShareReady:
            shareReadySession.clear()
            paletteModel?.shareReadyMappingCount = 0
            if var preview = currentPreview {
                preview.errorMessage = "Share-Ready mappings were cleared from volatile memory. Existing preview text was not changed."
                publish(preview)
            }
        case .startChain:
            guard let preview = currentPreview, !preview.isStreaming else { return }
            chainSession.start(with: preview.original)
            showPalette(.chain(chainSession))
        case .chainToggle(let id):
            chainSession.toggleInclusion(id: id)
            publishChain()
        case .chainMove(let id, let direction):
            chainSession.move(id: id, direction: direction)
            publishChain()
        case .chainSelectAll(let included):
            chainSession.setAllIncluded(included)
            publishChain()
        case .chainDelimiter(let delimiter):
            chainSession.setDelimiter(delimiter)
            publishChain()
        case .chainCopy:
            let combined = chainSession.combinedPreview
            guard chainSession.isActive, !combined.isEmpty else { return }
            do {
                try pasteService.copyResult(combined)
                chainSession.clear()
                paletteController.dismiss()
            } catch {
                presentExecutionError(error)
            }
        case .chainClear:
            chainSession.clear()
            paletteController.dismiss()
        case .copyResult:
            guard let preview = currentPreview, preview.canExport else {
                return
            }
            do {
                if let payload = preview.exportPayload {
                    try pasteService.copyResult(payload)
                } else {
                    try pasteService.copyResult(preview.output)
                }
                paletteController.dismiss()
            } catch {
                paletteController.dismiss()
                presentExecutionError(error)
            }
        case .sendToDevice:
            guard let preview = currentPreview, preview.canExport else { return }
            let approvedOutput = preview.output
            // Dismiss the HUD before focusing the handoff window. Otherwise
            // the HUD's focus-loss dismissal can hide the newly opened window.
            paletteController.dismiss()
            p2pHandoff.beginSending(approvedOutput)
            presentP2PHandoff()
        case .pasteCleaned:
            guard let preview = currentPreview, preview.canExport else {
                return
            }
            pasteExplicitly(preview.output, payload: preview.exportPayload)
        case .pasteOriginal:
            guard let preview = currentPreview else {
                return
            }
            pasteExplicitly(preview.original)
        }
    }

    /// App Intents entry point. It uses the same validated local pipeline but
    /// never presents a window or reads a pasteboard.
    private func transformForIntent(_ input: String) async throws -> String {
        guard !ThermalBudget.requiresDeterministicFallback(),
              let selectedModelIdentifier else {
            throw LocalModelIntentError.modelUnavailable
        }
        try await inferenceEngine.loadModel(identifier: selectedModelIdentifier)
        let stream = try await pipeline.inferenceStream(
            action: .rewrite,
            input: input,
            maxTokens: ThermalBudget.maximumTokens(requested: inferencePreferences.maximumOutputTokens)
        )
        for try await event in stream {
            if case .completed(let result) = event {
                guard result.validation.canExport, !result.output.isEmpty else {
                    throw LocalModelIntentError.emptyOutput
                }
                return result.output
            }
        }
        throw LocalModelIntentError.emptyOutput
    }

    func handleDeepLink(_ url: URL) {
        guard ClipGumDeepLink.destination(for: url) != nil else { return }
        openInferenceSettings()
    }

    private func runTransformation(_ action: SmartPasteAction) {
        guard let currentPreview, !currentPreview.isStreaming else {
            return
        }

        if action.isMechanical {
            let started = DispatchTime.now().uptimeNanoseconds
            let feature = DiagnosticFeature(action: action)
            do {
                if let result = try pipeline.mechanicalResult(
                    action: action,
                    input: currentPreview.original,
                    options: paletteModel?.developerOptions ?? DeveloperActionOptions(),
                    document: currentDocument
                ) {
                    publish(PalettePreview(deterministicResult: result, action: action))
                    if let feature {
                        diagnostics.record(
                            feature: feature,
                            latencyNanoseconds: DispatchTime.now().uptimeNanoseconds - started
                        )
                    }
                } else if let feature {
                    diagnostics.record(
                        feature: feature,
                        latencyNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                        error: .invalidInput
                    )
                }
            } catch {
                if let feature {
                    diagnostics.record(
                        feature: feature,
                        latencyNanoseconds: DispatchTime.now().uptimeNanoseconds - started,
                        error: diagnosticErrorCode(for: error)
                    )
                }
                restoreDeterministic(message: userFacingMessage(for: error))
            }
            return
        }

        if ThermalBudget.requiresDeterministicFallback() {
            restoreDeterministic(message: "Thermal pressure is critical. ClipGum kept the deterministic result and skipped local generation.")
            return
        }
        guard modelLoadTask == nil else {
            restoreDeterministic(message: "The selected model is already loading. Run again when it is Ready.")
            return
        }
        guard let selectedModelIdentifier else {
            restoreDeterministic(message: "✓ Nettoyé avec les règles déterministes. (Optionnel : Chargez un modèle IA dans les Réglages pour la reformulation générative)")
            return
        }

        let original = currentPreview.original
        let diagnosticStarted = DispatchTime.now().uptimeNanoseconds
        let diagnosticFeature = DiagnosticFeature(action: action)
        let baseline = cleaner.clean(original)
        let generationID = UUID()
        activeGenerationID = generationID
        var streaming = PalettePreview(deterministicResult: baseline, action: action)
        streaming.output = ""
        streaming.phase = .streaming
        publish(streaming)

        inferenceTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                if self.activeGenerationID == generationID {
                    self.activeGenerationID = nil
                    self.inferenceTask = nil
                }
            }
            do {
                // Idempotent when loaded; an idle-offloaded model reloads only
                // because the user explicitly selected Run.
                try await self.inferenceEngine.loadModel(identifier: selectedModelIdentifier)
                try Task.checkCancellation()
                let stream = try await self.pipeline.inferenceStream(
                    action: action,
                    input: original,
                    maxTokens: ThermalBudget.maximumTokens(
                        requested: self.inferencePreferences.maximumOutputTokens
                    )
                )
                for try await event in stream {
                    guard self.activeGenerationID == generationID,
                        var preview = self.currentPreview,
                        preview.isStreaming
                    else {
                        return
                    }
                    switch event {
                    case .chunk(let delta):
                        preview.output += delta
                        preview.streamedChunks += 1
                    case .completed(let result):
                        preview.action = result.action
                        preview.output = result.output
                        preview.phase = .completed
                        preview.validation = result.validation
                        preview.streamedChunks = result.streamedChunks
                        preview.errorMessage = nil
                        if let diagnosticFeature {
                            self.diagnostics.record(
                                feature: diagnosticFeature,
                                latencyNanoseconds: DispatchTime.now().uptimeNanoseconds - diagnosticStarted,
                                error: result.validation.canExport ? nil : .invariantBlocked
                            )
                        }
                    }
                    self.publish(preview)
                }
            } catch {
                guard self.activeGenerationID == generationID else {
                    return
                }
                if let diagnosticFeature {
                    self.diagnostics.record(
                        feature: diagnosticFeature,
                        latencyNanoseconds: DispatchTime.now().uptimeNanoseconds - diagnosticStarted,
                        error: error is CancellationError ? .cancelled : self.diagnosticErrorCode(for: error)
                    )
                }
                if !(error is CancellationError) {
                    self.restoreDeterministic(message: self.userFacingMessage(for: error))
                }
            }
        }
    }

    private func publish(_ preview: PalettePreview) {
        currentPreview = preview
        paletteModel?.shareReadyMappingCount = shareReadySession.mappingCount
        paletteModel?.content = .preview(preview)
    }

    private func publishChain() {
        paletteModel?.content = .chain(chainSession)
    }

    private func restoreDeterministic(message: String?) {
        guard let baseline = currentPreview?.deterministicBaseline else {
            return
        }
        let preview = PalettePreview(
            deterministicResult: baseline,
            action: .clean,
            errorMessage: message
        )
        paletteModel?.selectedAction = .clean
        publish(preview)
    }

    private func presentP2PHandoff() {
        if let p2pWindow {
            p2pWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 570, height: 610),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClipGum Local Handoff"
        window.contentViewController = NSHostingController(rootView: P2PHandoffView(controller: p2pHandoff))
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        p2pWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === p2pWindow else {
            return
        }
        p2pHandoff.stop()
        p2pWindow = nil
    }

    private func pasteExplicitly(_ text: String, payload: PasteboardPayload? = nil) {
        let target = targetApplication
        paletteController.dismiss()
        do {
            if let payload, payload.plainText == text {
                try pasteService.paste(payload, to: target)
            } else {
                try pasteService.paste(text, to: target)
            }
        } catch {
            presentExecutionError(error)
        }
    }

    private func chooseModel(backend: InferenceBackendKind) {
        guard inferenceTask == nil, modelLoadTask == nil else {
            presentModelMessage("Wait for the current model operation to finish, or Cancel the active transformation.")
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = backend == .gguf
        panel.canChooseDirectories = backend == .mlx
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Load Local Model"
        panel.message = backend == .mlx
            ? "Choose an MLX model directory containing config.json and safetensors weights."
            : "Choose a local GGUF instruct model."
        if backend == .gguf {
            panel.allowedFileTypes = ["gguf"]
        }

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        selectModel(url: url, backend: backend)
    }

    private func selectModel(url: URL, backend: InferenceBackendKind) {
        let access = SecurityScopedModelAccess(url: url)
        modelAccess = access
        let identifier = backend == .mlx
            ? ModelIdentifier.mlx(directory: url)
            : ModelIdentifier.gguf(file: url)
        selectedModelIdentifier = identifier

        modelLoadTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                self.modelLoadTask = nil
            }
            do {
                try await self.inferenceEngine.loadModel(identifier: identifier)
            } catch {
                if !(error is CancellationError) {
                    self.presentModelMessage(self.userFacingMessage(for: error))
                }
            }
        }
    }

    func loadDefaultModel() {
        let defaultId = "hf:\(ModelIdentifier.defaultHuggingFaceRepo)"
        loadModelByIdentifier(defaultId)
    }

    func loadModelByIdentifier(_ identifier: String) {
        guard inferenceTask == nil, modelLoadTask == nil else {
            presentModelMessage("Wait for the current model operation to finish, or Cancel the active transformation.")
            return
        }
        selectedModelIdentifier = identifier
        modelLoadTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                self.modelLoadTask = nil
            }
            do {
                try await self.inferenceEngine.loadModel(identifier: identifier)
            } catch {
                if !(error is CancellationError) {
                    self.presentModelMessage(self.userFacingMessage(for: error))
                }
            }
        }
    }

    private func unloadSelectedModel() {
        guard inferenceTask == nil, modelLoadTask == nil else {
            presentModelMessage("Wait for the current model operation to finish, or Cancel the active transformation.")
            return
        }
        modelLoadTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                self.modelLoadTask = nil
            }
            do {
                try await self.inferenceEngine.unloadModel()
                self.selectedModelIdentifier = nil
                self.modelAccess = nil
            } catch {
                self.presentModelMessage(self.userFacingMessage(for: error))
            }
        }
    }

    func copyDiagnosticsPayload(_ text: String) -> Bool {
        do {
            try DiagnosticPayloadSchema.validate(Data(text.utf8))
            try pasteService.copyResult(text)
            return true
        } catch {
            return false
        }
    }

    func clearAllData() {
        diagnostics.clearAllData()
        shareReadySession.clear()
        chainSession.clear()
        inferenceTask?.cancel()
        inferenceTask = nil
        activeGenerationID = nil
        currentPreview = nil
        currentDocument = nil
        paletteModel = nil
        targetApplication = nil
        p2pHandoff.stop()
        p2pWindow?.close()
        p2pWindow = nil
        paletteController.dismiss()
    }

    func replayOnboarding() {
        presentOnboardingIfNeeded(force: true)
    }

    private func presentOnboardingIfNeeded(force: Bool = false) {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = OnboardingController()
        guard force || !controller.isCompleted else { return }
        controller.onFinish = { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.onboardingController = nil
        }
        let rootView = OnboardingView(
            controller: controller,
            diagnostics: diagnostics,
            downloadController: modelDownloadController,
            onChooseModel: { [weak self] backend in
                self?.chooseModel(backend: backend)
            },
            onLoadVerifiedModel: { [weak self] verified in
                self?.selectModel(
                    url: verified.modelURL,
                    backend: verified.manifest.backend.inferenceBackend
                )
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 570),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to ClipGum"
        window.contentViewController = NSHostingController(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        onboardingController = controller
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func diagnosticErrorCode(for error: Error) -> DiagnosticErrorCode {
        guard let inferenceError = error as? InferenceEngineError else {
            return .invalidInput
        }
        switch inferenceError {
        case .invalidInput, .invalidIdentifier, .contextLimit:
            return .invalidInput
        case .inputTooLarge, .outputTooLarge:
            return .outputLimit
        case .invalidModel, .modelNotLoaded, .engineBusy, .unsupportedArchitecture:
            return .modelUnavailable
        case .modelTooLarge, .outOfMemory:
            return .modelOutOfMemory
        case .generationFailed:
            return .inferenceFailed
        }
    }

    func openInferenceSettings() {
        if let window = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let rootView = PublicBetaSettingsView(
            inference: inferencePreferences,
            updates: updateManager,
            diagnostics: diagnostics,
            policy: enterprisePolicy,
            rules: customRules,
            onCopyDiagnostics: { [weak self] text in
                self?.copyDiagnosticsPayload(text) ?? false
            },
            onClearAllData: { [weak self] in
                self?.clearAllData()
            },
            onReplayOnboarding: { [weak self] in
                self?.replayOnboarding()
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClipGum — Réglages & Modèles"
        window.contentViewController = NSHostingController(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func openLiveInspector() {
        if let window = inspectorWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClipGum — Inspecteur & Journal d'Audit en Direct"
        window.contentViewController = NSHostingController(rootView: LiveInspectorView())
        window.isReleasedWhenClosed = false
        window.center()
        inspectorWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func userFacingMessage(for error: Error) -> String {
        if let error = error as? InferenceEngineError,
            let description = error.errorDescription
        {
            return description
        }
        if let error = error as? JSONFormattingError,
            let description = error.errorDescription
        {
            return description
        }
        if let error = error as? JSONSyntaxError,
            let description = error.errorDescription
        {
            return description
        }
        if let error = error as? TypeScriptGenerationError,
            let description = error.errorDescription
        {
            return description
        }
        if let error = error as? SmartPastePipelineError,
            let description = error.errorDescription
        {
            return description
        }
        if let error = error as? RichTextWorkflowError,
            let description = error.errorDescription
        {
            return description
        }
        if let error = error as? TableWorkflowError,
            let description = error.errorDescription
        {
            return description
        }
        if let error = error as? HTMLScanError,
            let description = error.errorDescription
        {
            return description
        }
        return "Local inference failed. Partial model output was discarded; the deterministic result was restored."
    }

    private func presentModelMessage(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Local model"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func presentHotKeyError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Global shortcut unavailable"
        alert.informativeText = "\(error.localizedDescription) You can still use the ClipGum menu bar item."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func presentExecutionError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning

        if let pasteError = error as? PasteServiceError {
            switch pasteError {
            case .accessibilityRequired:
                alert.messageText = "Accessibility permission needed"
                alert.informativeText = "ClipGum needs Accessibility only to synthesize ⌘V. Your pasteboard was not changed. You can grant access, or invoke ClipGum again and choose Copy Result."
                alert.addButton(withTitle: "Open Accessibility Settings")
                alert.addButton(withTitle: "Cancel")
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn {
                    openSystemSettings(anchor: "Privacy_Accessibility")
                }
                return
            }
        }

        alert.messageText = "Clipboard action failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func openSystemSettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
