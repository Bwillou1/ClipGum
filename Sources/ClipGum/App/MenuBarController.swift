import AppKit
import Foundation

/// Owns the single NSStatusItem for the entire app lifetime.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let cleanAction: () -> Void
    private let radialAction: () -> Void
    private let chooseDefaultAction: () -> Void
    private let chooseMLXAction: () -> Void
    private let chooseGGUFAction: () -> Void
    private let unloadModelAction: () -> Void
    private let openSettingsAction: () -> Void
    private let openInspectorAction: () -> Void
    private let quitAction: () -> Void

    private let inferenceStatusMenuItem = NSMenuItem(
        title: "Idle · No model loaded",
        action: nil,
        keyEquivalent: ""
    )
    private var unloadMenuItem: NSMenuItem?

    init(
        cleanAction: @escaping () -> Void,
        radialAction: @escaping () -> Void,
        chooseDefaultAction: @escaping () -> Void,
        chooseMLXAction: @escaping () -> Void,
        chooseGGUFAction: @escaping () -> Void,
        unloadModelAction: @escaping () -> Void,
        openSettingsAction: @escaping () -> Void,
        openInspectorAction: @escaping () -> Void,
        quitAction: @escaping () -> Void
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.cleanAction = cleanAction
        self.radialAction = radialAction
        self.chooseDefaultAction = chooseDefaultAction
        self.chooseMLXAction = chooseMLXAction
        self.chooseGGUFAction = chooseGGUFAction
        self.unloadModelAction = unloadModelAction
        self.openSettingsAction = openSettingsAction
        self.openInspectorAction = openInspectorAction
        self.quitAction = quitAction
        super.init()
        configure()
    }

    func updateInferenceStatus(_ status: InferenceRuntimeStatus) {
        let title = menuTitle(for: status)
        inferenceStatusMenuItem.title = title
        statusItem.button?.toolTip = "ClipGum — \(title) · ⌘⇧V"
        statusItem.button?.setAccessibilityValue(title)
        switch status {
        case .ready:
            unloadMenuItem?.isEnabled = true
        case .idle, .loading, .generating, .unloading, .failed:
            unloadMenuItem?.isEnabled = false
        }
    }

    private func configure() {
        statusItem.button?.image = NSImage(
            systemSymbolName: "eraser.fill",
            accessibilityDescription: "ClipGum"
        ) ?? NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "ClipGum"
        )
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.setAccessibilityLabel("ClipGum")

        let menu = NSMenu()
        let cleanItem = NSMenuItem(
            title: "Smart Paste… (⌃Z / ⌘⇧V)",
            action: #selector(cleanMenuItemSelected),
            keyEquivalent: ""
        )
        cleanItem.target = self
        cleanItem.toolTip = "Lire le presse-papiers et ouvrir le panneau complet (Contrôle-Z)"
        menu.addItem(cleanItem)

        let radialItem = NSMenuItem(
            title: "Roue Radiale Curseur… (⌃X / ⌘⌥V)",
            action: #selector(radialMenuItemSelected),
            keyEquivalent: ""
        )
        radialItem.target = self
        radialItem.toolTip = "Entourer le curseur de la souris d'une roue d'actions rapides (Contrôle-X)"
        menu.addItem(radialItem)
        menu.addItem(.separator())

        let autoCleanItem = NSMenuItem(
            title: "⚡ Nettoyage Auto des URLs (Sans confirmation)",
            action: #selector(toggleAutoCleanSelected),
            keyEquivalent: ""
        )
        autoCleanItem.target = self
        autoCleanItem.state = AutoSanitizerService.shared.isAutoSanitizeURLsEnabled ? .on : .off
        autoCleanItem.toolTip = "Purger automatiquement les mouchards UTM/fbclid dès la copie d'un lien"
        menu.addItem(autoCleanItem)

        let devTokenItem = NSMenuItem(
            title: "🔑 Autoriser les Tokens en clair (Mode Développeur)",
            action: #selector(toggleDevTokenSelected),
            keyEquivalent: ""
        )
        devTokenItem.target = self
        devTokenItem.state = AutoSanitizerService.shared.isDeveloperTokenModeEnabled ? .on : .off
        devTokenItem.toolTip = "Conserver vos jetons d'API (GitHub, OpenAI, AWS) intacts pour les coller"
        menu.addItem(devTokenItem)
        menu.addItem(.separator())

        inferenceStatusMenuItem.isEnabled = false
        menu.addItem(inferenceStatusMenuItem)
        menu.addItem(makeItem(
            title: "Load Default Model (Bonsai 4B MLX)",
            action: #selector(chooseDefaultSelected)
        ))
        menu.addItem(makeItem(
            title: "Choose MLX Model Folder…",
            action: #selector(chooseMLXSelected)
        ))
        menu.addItem(makeItem(
            title: "Choose GGUF Model…",
            action: #selector(chooseGGUFSelected)
        ))
        let unloadItem = makeItem(
            title: "Unload Model",
            action: #selector(unloadModelSelected)
        )
        unloadItem.isEnabled = false
        unloadMenuItem = unloadItem
        menu.addItem(unloadItem)
        menu.addItem(makeItem(
            title: "Inspecteur & Journal en direct… (⌘L)",
            action: #selector(openInspectorSelected)
        ))
        menu.addItem(makeItem(
            title: "Inference & Model Settings…",
            action: #selector(openSettingsSelected)
        ))
        menu.addItem(.separator())

        let invariantItem = NSMenuItem(
            title: "On demand only · No history · Local inference",
            action: nil,
            keyEquivalent: ""
        )
        invariantItem.isEnabled = false
        menu.addItem(invariantItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit ClipGum",
            action: #selector(quitMenuItemSelected),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        updateInferenceStatus(.idle)
    }

    private func makeItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func menuTitle(for status: InferenceRuntimeStatus) -> String {
        switch status {
        case .idle:
            return "● IA en veille · Aucun modèle chargé"
        case .loading(let kind):
            return "⏳ Chargement du modèle \(kind.rawValue.uppercased())…"
        case .ready(let kind, let residentBytes):
            let memory = ProcessMemoryUsage.formatted(residentBytes)
            return "● IA Prête (\(kind.rawValue.uppercased())) · \(memory)"
        case .generating(let kind, _):
            return "⚡ Inférence locale en cours (\(kind.rawValue.uppercased()))…"
        case .unloading:
            return "Déchargement du modèle…"
        case .failed(let message):
            return "⚠️ \(message)"
        }
    }

    @objc private func cleanMenuItemSelected() {
        cleanAction()
    }

    @objc private func radialMenuItemSelected() {
        radialAction()
    }

    @objc private func chooseDefaultSelected() {
        chooseDefaultAction()
    }

    @objc private func chooseMLXSelected() {
        chooseMLXAction()
    }

    @objc private func chooseGGUFSelected() {
        chooseGGUFAction()
    }

    @objc private func unloadModelSelected() {
        unloadModelAction()
    }

    @objc private func openSettingsSelected() {
        openSettingsAction()
    }

    @objc private func openInspectorSelected() {
        openInspectorAction()
    }

    @objc private func toggleAutoCleanSelected(_ sender: NSMenuItem) {
        AutoSanitizerService.shared.isAutoSanitizeURLsEnabled.toggle()
        sender.state = AutoSanitizerService.shared.isAutoSanitizeURLsEnabled ? .on : .off
    }

    @objc private func toggleDevTokenSelected(_ sender: NSMenuItem) {
        AutoSanitizerService.shared.isDeveloperTokenModeEnabled.toggle()
        sender.state = AutoSanitizerService.shared.isDeveloperTokenModeEnabled ? .on : .off
    }

    @objc private func quitMenuItemSelected() {
        quitAction()
    }
}
