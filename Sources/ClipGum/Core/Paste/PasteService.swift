import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ClipGumCore
import Foundation

enum PasteServiceError: LocalizedError {
    case accessibilityRequired

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired:
            return "Accessibility permission is required to send ⌘V. The pasteboard was not changed."
        }
    }
}

/// Explicit copy/paste execution. Nothing in this type runs on a schedule or
/// observes the pasteboard; the only delayed work is a one-shot focus handoff.
@MainActor
final class PasteService {
    private let pasteboard: SystemPasteboard
    private let accessibilityTrusted: (Bool) -> Bool
    private let applicationActivator: (NSRunningApplication?) -> Void
    private let keystrokePoster: () -> Void
    private let focusSettleDelay: TimeInterval
    private let requiresSecretRedaction: () -> Bool

    init(
        pasteboard: SystemPasteboard,
        accessibilityTrusted: @escaping (Bool) -> Bool = SystemPermissionCenter.accessibilityTrusted,
        applicationActivator: @escaping (NSRunningApplication?) -> Void = PasteService.activate,
        keystrokePoster: @escaping () -> Void = PasteService.postCommandV,
        focusSettleDelay: TimeInterval = 0.05,
        requiresSecretRedaction: @escaping () -> Bool = { false }
    ) {
        self.pasteboard = pasteboard
        self.accessibilityTrusted = accessibilityTrusted
        self.applicationActivator = applicationActivator
        self.keystrokePoster = keystrokePoster
        self.focusSettleDelay = focusSettleDelay
        self.requiresSecretRedaction = requiresSecretRedaction
    }

    private func protectedText(_ text: String) -> String {
        guard requiresSecretRedaction() else { return text }
        return DeterministicTransforms.redactSecrets(in: text).output
    }

    private func writePayloadForExplicitAction(_ payload: PasteboardPayload) throws {
        if requiresSecretRedaction() {
            // Scrubbing RTF/HTML independently could leave a secret in an
            // alternate flavor. Managed mode therefore emits one safe plain
            // flavor rather than preserving a richer but unverifiable payload.
            try pasteboard.writeTextForExplicitUserAction(protectedText(payload.plainText))
        } else {
            try pasteboard.writeDocumentForExplicitUserAction(payload)
        }
    }

    func copyResult(_ text: String) throws {
        try pasteboard.writeTextForExplicitUserAction(protectedText(text))
    }

    func copyResult(_ payload: PasteboardPayload) throws {
        try writePayloadForExplicitAction(payload)
    }

    func paste(_ text: String, to targetApplication: NSRunningApplication?) throws {
        // Check before clearing the pasteboard: denial is non-destructive.
        guard accessibilityTrusted(true) else {
            throw PasteServiceError.accessibilityRequired
        }

        try pasteboard.writeTextForExplicitUserAction(protectedText(text))
        finishPaste(to: targetApplication)
    }

    func paste(_ payload: PasteboardPayload, to targetApplication: NSRunningApplication?) throws {
        guard accessibilityTrusted(true) else {
            throw PasteServiceError.accessibilityRequired
        }

        try writePayloadForExplicitAction(payload)
        finishPaste(to: targetApplication)
    }

    private func finishPaste(to targetApplication: NSRunningApplication?) {
        applicationActivator(targetApplication)

        // This is not polling. It yields one focus handoff before the explicit
        // paste keystroke, matching the approach used by Maccy and Clipy.
        DispatchQueue.main.asyncAfter(deadline: .now() + focusSettleDelay) {
            self.keystrokePoster()
        }
    }

    private static func activate(_ application: NSRunningApplication?) {
        if let application {
            _ = application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        } else {
            NSApp.hide(nil)
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let keyCode = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
