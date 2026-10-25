import ClipGumCore
import Combine
import Foundation

@MainActor
final class P2PHandoffController: ObservableObject {
    @Published private(set) var devices: [P2PDevice] = []
    @Published private(set) var pairingCode = ""
    @Published private(set) var status: P2PServiceStatus = .idle
    @Published private(set) var statusMessage = "Start a local handoff to discover nearby ClipGum devices."
    @Published private(set) var receivedText = ""
    @Published private(set) var isSending = false
    @Published private(set) var isPresented = false

    /// Injected by AppDelegate. The controller itself has no pasteboard access.
    var copyReceivedHandler: (String) -> Bool = { _ in false }
    var dismissHandler: () -> Void = {}

    private let service: LocalP2PService
    private var pendingText: String?
    private var sendInitiated = false

    init(service: LocalP2PService = LocalP2PService()) {
        self.service = service
        service.onDevicesChanged = { [weak self] in self?.devices = $0 }
        service.onPairingCode = { [weak self] code in
            self?.pairingCode = code
            self?.statusMessage = "Compare this six-digit code with the other device, then confirm on both devices."
        }
        service.onStatusChanged = { [weak self] status in
            guard let self else { return }
            self.status = status
            if status == .closed {
                self.pendingText = nil
                self.sendInitiated = false
                self.isSending = false
                self.statusMessage = "The local connection ended. No payload was retained."
            }
        }
        service.onReady = { [weak self] in
            guard let self else { return }
            if self.pendingText == nil {
                self.statusMessage = "Authenticated local channel ready. Waiting for one explicit payload."
            }
            self.sendAfterReadyIfNeeded()
        }
        service.onDeliveryAcknowledged = { [weak self] in
            guard let self else { return }
            self.pendingText = nil
            self.sendInitiated = false
            self.isSending = false
            self.statusMessage = "Delivered over the authenticated local channel. The handoff buffer was cleared."
        }
        service.onReceivedSanitizedText = { [weak self] text in
            guard let self else { return }
            self.receivedText = text
            self.statusMessage = "Received sanitized text. Review it, then choose Copy explicitly if desired."
        }
        service.onError = { [weak self] error in
            guard let self else { return }
            self.pendingText = nil
            self.sendInitiated = false
            self.isSending = false
            self.statusMessage = Self.safeMessage(error)
        }
    }

    func beginSending(_ text: String) {
        // Re-clean at the final handoff boundary, even when the preview already
        // passed deterministic or validated model processing.
        pendingText = RuleCleaningService().clean(text).cleaned
        sendInitiated = false
        isSending = true
        receivedText = ""
        pairingCode = ""
        isPresented = true
        startService()
    }

    func beginReceiving() {
        pendingText = nil
        sendInitiated = false
        isSending = false
        receivedText = ""
        pairingCode = ""
        isPresented = true
        startService()
    }

    func select(_ device: P2PDevice) {
        do {
            try service.connect(to: device)
            statusMessage = "Connecting directly; no relay or cloud service is used."
        } catch {
            statusMessage = Self.safeMessage(error)
        }
    }

    func confirmPairing() {
        guard !pairingCode.isEmpty else { return }
        do {
            try service.confirmPairing(code: pairingCode)
            statusMessage = "Confirmation sent. Waiting for the other device’s explicit confirmation."
        } catch {
            statusMessage = Self.safeMessage(error)
        }
    }

    func copyReceived() {
        guard !receivedText.isEmpty, copyReceivedHandler(receivedText) else { return }
        receivedText = ""
        statusMessage = "Copied sanitized text after your explicit choice."
    }

    func clearReceived() {
        receivedText = ""
        statusMessage = "Received text cleared from the preview."
    }

    func stop() {
        service.stop()
        pendingText = nil
        sendInitiated = false
        isSending = false
        receivedText = ""
        pairingCode = ""
        isPresented = false
        status = .idle
    }

    func close() {
        stop()
        dismissHandler()
    }

    private func startService() {
        service.stop()
        do {
            try service.start()
            statusMessage = "Discovering paired sessions locally over Bonjour / AWDL."
        } catch {
            statusMessage = Self.safeMessage(error)
        }
    }

    private func sendAfterReadyIfNeeded() {
        guard let pendingText, !sendInitiated else { return }
        do {
            sendInitiated = true
            try service.sendSanitized(pendingText)
            statusMessage = "Sending the explicitly sanitized payload. Waiting for an encrypted acknowledgement."
        } catch {
            sendInitiated = false
            isSending = false
            statusMessage = Self.safeMessage(error)
        }
    }

    private static func safeMessage(_ error: Error) -> String {
        if let error = error as? P2PError, let description = error.errorDescription {
            return description
        }
        return "The local handoff ended safely; no content was logged."
    }
}
