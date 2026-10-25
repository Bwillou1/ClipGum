import ClipGumCore
import SwiftUI
import UIKit

@MainActor
final class MobileHandoffModel: ObservableObject {
    @Published private(set) var devices: [P2PDevice] = []
    @Published private(set) var pairingCode = ""
    @Published private(set) var status = "Local discovery is off until you choose an action."
    @Published private(set) var receivedText = ""
    @Published private(set) var running = false

    private let service = LocalP2PService()
    private let initialText: String
    private var pendingText: String?
    private var sendStarted = false

    var canSend: Bool { !initialText.isEmpty }

    init(initialText: String) {
        self.initialText = initialText
        service.onDevicesChanged = { [weak self] in self?.devices = $0 }
        service.onPairingCode = { [weak self] in
            self?.pairingCode = $0
            self?.status = "Compare the code with the other device, then confirm on both."
        }
        service.onReady = { [weak self] in self?.sendAfterReady() }
        service.onDeliveryAcknowledged = { [weak self] in
            self?.pendingText = nil
            self?.sendStarted = false
            self?.status = "Delivered and cleared from the handoff buffer."
        }
        service.onReceivedSanitizedText = { [weak self] in
            self?.receivedText = $0
            self?.status = "Received sanitized text. Copy only after reviewing it."
        }
        service.onStatusChanged = { [weak self] state in
            guard let self, state == .closed else { return }
            self.pendingText = nil
            self.sendStarted = false
            self.status = "The local connection ended; no payload is queued."
        }
        service.onError = { [weak self] error in
            guard let self else { return }
            self.pendingText = nil
            self.sendStarted = false
            self.status = error.localizedDescription
        }
    }

    func startSending() {
        pendingText = MobileCleaningService().clean(initialText).output
        sendStarted = false
        start()
    }

    func startReceiving() {
        pendingText = nil
        sendStarted = false
        start()
    }

    func select(_ device: P2PDevice) {
        do { try service.connect(to: device) } catch { status = error.localizedDescription }
    }

    func confirm() {
        do {
            try service.confirmPairing(code: pairingCode)
            status = "Confirmation sent. Waiting for mutual confirmation."
        } catch { status = error.localizedDescription }
    }

    func copyReceived() {
        guard !receivedText.isEmpty else { return }
        // This is the only mobile pasteboard write in the handoff view and it
        // happens only after the user presses Copy.
        UIPasteboard.general.string = receivedText
        receivedText = ""
        status = "Copied after your explicit choice."
    }

    func stop() {
        service.stop()
        pendingText = nil
        sendStarted = false
        receivedText = ""
        pairingCode = ""
        running = false
        status = "Local discovery is off."
    }

    private func start() {
        service.stop()
        do {
            try service.start()
            running = true
            status = "Discovering nearby ClipGum devices over Bonjour / AWDL."
        } catch { status = error.localizedDescription }
    }

    private func sendAfterReady() {
        guard let pendingText, !sendStarted else { return }
        do {
            sendStarted = true
            try service.sendSanitized(pendingText)
            status = "Sending sanitized text; waiting for acknowledgement."
        } catch {
            sendStarted = false
            status = error.localizedDescription
        }
    }
}

@MainActor
struct MobileHandoffView: View {
    @StateObject private var model: MobileHandoffModel

    init(initialText: String) {
        _model = StateObject(wrappedValue: MobileHandoffModel(initialText: initialText))
    }

    var body: some View {
        List {
            Section("Manual local handoff") {
                Text(model.status)
                if !model.running {
                    if model.canSend {
                        Button("Start & Send Sanitized") { model.startSending() }
                    }
                    Button("Receive Only") { model.startReceiving() }
                } else {
                    Button("Stop Local Discovery") { model.stop() }
                }
            }
            if !model.pairingCode.isEmpty {
                Section("Pairing") {
                    Text(model.pairingCode)
                        .font(.system(.largeTitle, design: .monospaced).bold())
                    Button("Codes Match") { model.confirm() }
                }
            }
            if !model.receivedText.isEmpty {
                Section("Received sanitized preview") {
                    Text(model.receivedText).textSelection(.enabled)
                    Button("Copy Sanitized") { model.copyReceived() }
                }
            } else {
                Section("Nearby devices") {
                    ForEach(model.devices) { device in
                        Button(device.name) { model.select(device) }
                    }
                }
            }
        }
        .navigationTitle("Local Handoff")
        .onDisappear { model.stop() }
    }
}
