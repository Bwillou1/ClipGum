import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let cleaner = RuleCleaningService()
    private let pasteboard = SystemPasteboard()
    private let paletteController = PalettePanelController()
    private lazy var pasteService = PasteService(pasteboard: pasteboard)

    let inferencePreferences: InferencePreferences
    private let inferenceEngine: LocalInferenceEngine
    private let pipeline: SmartPastePipeline

    private var menuBarController: MenuBarController?
    private var hotKey: GlobalHotKey?
    private var paletteModel: PaletteModel?
    private var currentPreview: PalettePreview?
    private var targetApplication: NSRunningApplication?
    private var inferenceTask: Task<Void, Never>?
    private var modelLoadTask: Task<Void, Never>?
    private var activeGenerationID: UUID?
    private var selectedModelIdentifier: String?
    private var modelAccess: SecurityScopedModelAccess?

    override init() {
        let preferences = InferencePreferences()
        let engine = LocalInferenceEngine(configuration: preferences.configuration)
        inferencePreferences = preferences
        inferenceEngine = engine
        pipeline = SmartPastePipeline(
            engine: engine,
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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey?.invalidate()
        inferenceTask?.cancel()
        modelLoadTask?.cancel()
        modelAccess = nil
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

        switch pasteboard.readTextForExplicitUserAction() {
        case .text(let original):
            let preview = PalettePreview(deterministicResult: cleaner.clean(original))
            currentPreview = preview
            showPalette(.preview(preview))
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
                title: "No plain text found",
                detail: "ClipGum handles one plain-text clipboard item. Copy text, then invoke ClipGum again.",
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

    private func showPalette(_ content: PaletteContent) {
        if case .message = content {
            currentPreview = nil
        }

        let model = PaletteModel(content: content)
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
        case .copyResult:
            guard let preview = currentPreview, preview.canExport else {
                return
            }
            do {
                try pasteService.copyResult(preview.output)
                paletteController.dismiss()
            } catch {
                paletteController.dismiss()
                presentExecutionError(error)
            }
        case .pasteCleaned:
            guard let preview = currentPreview, preview.canExport else {
                return
            }
            pasteExplicitly(preview.output)
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
            do {
                if let result = try pipeline.mechanicalResult(
                    action: action,
                    input: currentPreview.original
                ) {
                    publish(PalettePreview(deterministicResult: result, action: action))
                }
            } catch {
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
                    }
                    self.publish(preview)
                }
            } catch {
                guard self.activeGenerationID == generationID else {
                    return
                }
                if !(error is CancellationError) {
                    self.restoreDeterministic(message: self.userFacingMessage(for: error))
                }
            }
        }
    }

    private func publish(_ preview: PalettePreview) {
        currentPreview = preview
        paletteModel?.content = .preview(preview)
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

    private func pasteExplicitly(_ text: String) {
        let target = targetApplication
        paletteController.dismiss()
        do {
            try pasteService.paste(text, to: target)
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

    private func openInferenceSettings() {
        NSApp.activate(ignoringOtherApps: true)
        _ = NSApp.sendAction(Selector(("showSettingsWindow:")), from: nil)
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
        if let error = error as? SmartPastePipelineError,
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
