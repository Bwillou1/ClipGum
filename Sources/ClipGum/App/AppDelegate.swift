import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let cleaner = RuleCleaningService()
    private let richTextSanitizer = RichTextSanitizer()
    private let pasteboard = SystemPasteboard()
    private let shareReadySession: ShareReadySession
    private let paletteController = PalettePanelController()
    private var chainSession = ChainCopySession()
    private lazy var pasteService = PasteService(pasteboard: pasteboard)

    let inferencePreferences: InferencePreferences
    let updateManager: UpdateManager
    let diagnostics: DiagnosticsEngine
    private let inferenceEngine: LocalInferenceEngine
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

    override init() {
        let preferences = InferencePreferences()
        let engine = LocalInferenceEngine(configuration: preferences.configuration)
        let shareReady = ShareReadySession()
        inferencePreferences = preferences
        inferenceEngine = engine
        shareReadySession = shareReady
        updateManager = UpdateManager()
        diagnostics = DiagnosticsEngine()
        modelDownloadController = ModelDownloadController()
        pipeline = SmartPastePipeline(
            engine: engine,
            shareReadySession: shareReady,
            configuration: preferences.configuration
        )
        super.init()

        preferences.onChange = { configuration in
            Task {
                await engine.updateConfiguration(configuration)
            }
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(
            cleanAction: { [weak self] in
                self?.handleExplicitUserTrigger()
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
            quitAction: {
                NSApp.terminate(nil)
            }
        )

        Task {
            await inferenceEngine.setStatusHandler { [weak self] status in
                Task { @MainActor in
                    self?.menuBarController?.updateInferenceStatus(status)
                }
            }
        }

        let hotKey = GlobalHotKey { [weak self] in
            Task { @MainActor in
                self?.handleExplicitUserTrigger()
            }
        }
        self.hotKey = hotKey

        do {
            try hotKey.registerCommandShiftV()
        } catch {
            presentHotKeyError(error)
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
        onboardingWindow?.close()
        onboardingWindow = nil
        onboardingController = nil
    }

    /// The only production entry point that reads the general pasteboard.
    private func handleExplicitUserTrigger() {
        if paletteController.isPresented {
            paletteController.dismiss()
            return
        }

        let frontmost = NSWorkspace.shared.frontmostApplication
        targetApplication = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            ? nil
            : frontmost

        let appProfile = OfficeAppProfileResolver.profile(application: frontmost)
        switch pasteboard.readDocumentForExplicitUserAction() {
        case .document(let document):
            handleCapturedDocument(document, appProfile: appProfile)
        case .text(let original):
            handleCapturedDocument(
                PasteboardDocument(plainText: original),
                appProfile: appProfile
            )
        case .accessDenied:
            showPalette(.message(PaletteMessage(
                title: "Pasteboard access is denied",
                detail: "ClipGum did not read the clipboard. Allow ClipGum in System Settings → Privacy & Security → Paste from Other Apps, then invoke ⌘⇧V again.",
                showsPrivacySettings: true
            )))
        case .excluded:
            showPalette(.message(PaletteMessage(
                title: "Sensitive clipboard skipped",
                detail: "The source marked this item as concealed, transient, auto-generated, or a known password-manager value. ClipGum inspected metadata only and did not read its text."
            )))
        case .noText:
            showPalette(.message(PaletteMessage(
                title: "No supported text found",
                detail: "ClipGum handles one plain-text, public.html, or public.rtf item. Copy a single text selection, then invoke ClipGum again.",
                systemImage: "doc.questionmark"
            )))
        case .emptyText:
            showPalette(.message(PaletteMessage(
                title: "Clipboard text is empty",
                detail: "Copy some text, then invoke ClipGum again.",
                systemImage: "doc"
            )))
        case .multipleItems:
            showPalette(.message(PaletteMessage(
                title: "Multiple items not supported",
                detail: "ClipGum intentionally handles one text item at a time. Copy a single text selection and try again.",
                systemImage: "rectangle.stack"
            )))
        }
    }

    private func handleCapturedDocument(
        _ document: PasteboardDocument,
        appProfile: OfficeAppProfile
    ) {
        do {
            let original = try richTextSanitizer.plainText(from: document)
            guard !original.isEmpty else {
                showPalette(.message(PaletteMessage(
                    title: "Clipboard text is empty",
                    detail: "The captured flavors contain no visible text. Copy some text, then invoke ClipGum again.",
                    systemImage: "doc"
                )))
                return
            }
            if chainSession.isActive {
                chainSession.add(original)
                currentPreview = nil
                showPalette(.chain(chainSession))
            } else {
                let preview = PalettePreview(deterministicResult: cleaner.clean(original))
                currentPreview = preview
                showPalette(.preview(preview), document: document, appProfile: appProfile)
            }
        } catch {
            showPalette(.message(PaletteMessage(
                title: "Rich text could not be read",
                detail: userFacingMessage(for: error),
                systemImage: "doc.questionmark"
            )))
        }
    }

    private func showPalette(
        _ content: PaletteContent,
        document: PasteboardDocument? = nil,
        appProfile: OfficeAppProfile? = nil
    ) {
        currentDocument = document
        switch content {
        case .message, .chain:
            currentPreview = nil
        case .preview:
            break
        }

        let model = PaletteModel(
            content: content,
            document: document,
            appProfile: appProfile
        )
        model.shareReadyMappingCount = shareReadySession.mappingCount
        paletteModel = model
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

        guard modelLoadTask == nil else {
            restoreDeterministic(message: "The selected model is already loading. Run again when it is Ready.")
            return
        }
        guard let selectedModelIdentifier else {
            restoreDeterministic(message: InferenceEngineError.modelNotLoaded.localizedDescription)
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
                    maxTokens: self.inferencePreferences.maximumOutputTokens
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

    private func openInferenceSettings() {
        NSApp.activate(ignoringOtherApps: true)
        _ = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
