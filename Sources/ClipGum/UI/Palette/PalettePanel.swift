import AppKit

/// Borderless, floating SwiftUI host with explicit key-focus support.
final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 520),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        animationBehavior = .none
        title = "ClipGum"
        setAccessibilityLabel("ClipGum cleaning preview")
    }
}
