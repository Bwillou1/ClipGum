import AppKit
import ApplicationServices
import Foundation

@MainActor
enum SystemPermissionCenter {
    private static var hasPromptedOnce = false

    static func accessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        if AXIsProcessTrustedWithOptions([key: false] as CFDictionary) {
            return true
        }

        // Preserve Clipy's production fallback for ad-hoc signed builds where
        // the focused-application AX query is already permitted.
        var value: CFTypeRef?
        let queryResult = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedApplicationAttribute as CFString,
            &value
        )
        if queryResult == .success || queryResult == .noValue {
            return true
        }
        guard prompt, !hasPromptedOnce else { return false }
        hasPromptedOnce = true
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        openSystemSettings(anchor: "Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        // ClipGum registers a hotkey; it does not run an input event tap. Open
        // guidance only when the user chooses it, without requesting access.
        openSystemSettings(anchor: "Privacy_ListenEvent")
    }

    static func openPasteboardSettings() {
        openSystemSettings(anchor: "Privacy_Pasteboard")
    }

    private static func openSystemSettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

struct PermissionRecoveryGuide: Equatable {
    let canPaste: Bool
    let title: String
    let recoverySteps: [String]

    static func accessibility(isTrusted: Bool) -> PermissionRecoveryGuide {
        if isTrusted {
            return PermissionRecoveryGuide(
                canPaste: true,
                title: "Accessibility granted",
                recoverySteps: ["Invoke ⌘⇧V again, then choose Paste Cleaned."]
            )
        }
        return PermissionRecoveryGuide(
            canPaste: false,
            title: "Accessibility not granted",
            recoverySteps: [
                "Choose Enable & Check Accessibility.",
                "Enable ClipGum in System Settings → Privacy & Security → Accessibility.",
                "Return to ClipGum and choose Check Again; Copy Result remains available without this permission."
            ]
        )
    }
}
