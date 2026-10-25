import AppKit
import Foundation

/// Automatic background sanitizer that cleans URLs immediately upon copying
/// and safely preserves developer tokens/secrets so users never lose their API keys.
@MainActor
final class AutoSanitizerService {
    static let shared = AutoSanitizerService()

    private var timer: Timer?
    private var lastChangeCount: Int = -1
    private let urlCleaner = URLTrackingCleaner()
    private let secretRedactor = SecretRedactor(placeholder: "[SECRET_REDACTED]")

    /// Whether automatic background URL sanitization is active without asking permission
    var isAutoSanitizeURLsEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: "clipgum_auto_sanitize_urls") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "clipgum_auto_sanitize_urls")
        }
    }

    /// Whether tokens and secrets are allowed to be pasted unmasked (Developer mode)
    var isDeveloperTokenModeEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: "clipgum_allow_raw_tokens") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "clipgum_allow_raw_tokens")
        }
    }

    /// Tracks if the last copied clipboard item contained a detected API token/secret
    private(set) var hasDetectedTokenInClipboard: Bool = false
    private(set) var lastRawToken: String? = nil

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPasteboard()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkPasteboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Guard against sensitive/concealed items (1Password, Bitwarden, etc.)
        let types = Set(NSPasteboard.general.types?.map(\.rawValue) ?? [])
        if PasteboardTypePolicy.firstIgnoredMarker(in: types) != nil {
            return
        }

        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            hasDetectedTokenInClipboard = false
            lastRawToken = nil
            return
        }

        // 1. Detect if clipboard contains a Secret / API key
        let secretCheck = secretRedactor.redactSecrets(in: text)
        if secretCheck.changeCount > 0 {
            hasDetectedTokenInClipboard = true
            lastRawToken = text
            // In developer mode, we deliberately preserve the real token so developers can paste it!
            LiveInspectorEngine.shared.record(
                trigger: "Presse-papiers (Copie)",
                contentType: "🔑 Secret / Jeton Détecté",
                original: text,
                cleaned: isDeveloperTokenModeEnabled ? text : secretCheck.output,
                trackersRemoved: 0,
                secretsRedacted: isDeveloperTokenModeEnabled ? 0 : secretCheck.changeCount,
                latencyMs: 1.0,
                actionName: isDeveloperTokenModeEnabled ? "Jeton préservé en clair (Mode Dév)" : "Jeton masqué"
            )
            if !isDeveloperTokenModeEnabled {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(secretCheck.output, forType: .string)
                lastChangeCount = NSPasteboard.general.changeCount
            }
            return
        } else {
            hasDetectedTokenInClipboard = false
            lastRawToken = nil
        }

        // 2. Auto-sanitize URLs without asking permission
        guard isAutoSanitizeURLsEnabled else { return }

        let result = urlCleaner.stripTrackingParameters(in: text)
        if result.changeCount > 0 && result.output != text {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result.output, forType: .string)
            lastChangeCount = NSPasteboard.general.changeCount

            LiveInspectorEngine.shared.record(
                trigger: "⚡ Auto-Clean Copie (Sans confirmation)",
                contentType: "🔗 URL Traquée",
                original: text,
                cleaned: result.output,
                trackersRemoved: result.changeCount,
                secretsRedacted: 0,
                latencyMs: 0.8,
                actionName: "Auto-Sanitize URL"
            )
        }
    }
}
