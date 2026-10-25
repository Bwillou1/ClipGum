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
            title: "Smart Paste… (⌘⇧V)",
            action: #selector(cleanMenuItemSelected),
            keyEquivalent: ""
        )
        cleanItem.target = self
        cleanItem.toolTip = "Read the current clipboard once and show full preview HUD"
        menu.addItem(cleanItem)

        let radialItem = NSMenuItem(
            title: "Mouse Radial Wheel… (⌘⌥V)",
            action: #selector(radialMenuItemSelected),
            keyEquivalent: ""
        )
        radialItem.target = self
        radialItem.toolTip = "Surround mouse cursor with quick circular action wheel"
        menu.addItem(radialItem)
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
            return "Idle · No model loaded"
        case .loading(let kind):
            return "Loading \(kind.rawValue) model…"
        case .ready(let kind, let residentBytes):
            let memory = ProcessMemoryUsage.formatted(residentBytes)
            return "Ready · Model Loaded · \(memory) RAM · \(kind.rawValue)"
        case .generating(let kind, _):
            return "Model Loaded · Generating locally · \(kind.rawValue)"
        case .unloading:
            return "Unloading model…"
        case .failed(let message):
            return message
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

    @objc private func quitMenuItemSelected() {
        quitAction()
    }
}
