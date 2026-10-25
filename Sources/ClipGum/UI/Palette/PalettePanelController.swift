import AppKit
import SwiftUI

@MainActor
final class PalettePanelController: NSObject, NSWindowDelegate {
    private let panel = PalettePanel()
    private var escapeMonitor: Any?
    private var onDismiss: (() -> Void)?
    private var model: PaletteModel?

    private(set) var isPresented = false

    override init() {
        super.init()
        panel.delegate = self
    }

    func show(
        model: PaletteModel,
        onAction: @escaping (PaletteAction) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        let rootView = PaletteView(model: model, onAction: onAction)
        self.model = model
        panel.contentViewController = NSHostingController(rootView: rootView)
        panel.setContentSize(NSSize(
            width: model.content.panelSize.width,
            height: model.content.panelSize.height
        ))
        positionNearScreenCenter()
        self.onDismiss = onDismiss
        isPresented = true
        installEscapeMonitor()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func showRadial(
        model: PaletteModel,
        onAction: @escaping (PaletteAction) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        let rootView = RadialPaletteView(
            model: model,
            onAction: onAction,
            onDismiss: { [weak self] in self?.dismiss() }
        )
        self.model = model
        panel.contentViewController = NSHostingController(rootView: rootView)
        panel.setContentSize(NSSize(width: 340, height: 340))
        positionAroundMouse()
        self.onDismiss = onDismiss
        isPresented = true
        installEscapeMonitor()

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func dismiss() {
        guard isPresented else {
            return
        }
        isPresented = false
        removeEscapeMonitor()
        panel.orderOut(nil)
        // Do not retain Before/After text in a hidden hosting controller.
        panel.contentViewController = nil
        panel.contentView = nil
        model = nil

        let completion = onDismiss
        onDismiss = nil
        completion?()

        // If another app was just clicked, do not fight that focus decision.
        if NSApp.isActive {
            NSApp.hide(nil)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Covers outside clicks and focus loss without a global event monitor.
        dismiss()
    }

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { // Escape
                return event
            }
            Task { @MainActor in
                self?.dismiss()
            }
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    private func positionAroundMouse() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(mouseLocation)
        }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            panel.center()
            return
        }

        let size = panel.frame.size
        let targetX = mouseLocation.x - size.width / 2
        let targetY = mouseLocation.y - size.height / 2
        let x = min(max(targetX, visibleFrame.minX), visibleFrame.maxX - size.width)
        let y = min(max(targetY, visibleFrame.minY), visibleFrame.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func positionNearScreenCenter() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: {
            $0.frame.contains(mouseLocation)
        }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            panel.center()
            return
        }

        let size = panel.frame.size
        let centeredX = visibleFrame.midX - size.width / 2
        let centeredY = visibleFrame.midY - size.height / 2
        let x = min(max(centeredX, visibleFrame.minX), visibleFrame.maxX - size.width)
        let y = min(max(centeredY, visibleFrame.minY), visibleFrame.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    deinit {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
    }
}
