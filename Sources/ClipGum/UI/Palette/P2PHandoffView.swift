import ClipGumCore
import SwiftUI

@MainActor
struct P2PHandoffView: View {
    @ObservedObject var controller: P2PHandoffController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Send Sanitized to Device").font(.title2.bold())
                    Text("Manual local handoff · Bonjour / AWDL · No cloud relay")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("Local only", systemImage: "lock.shield.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            }

            Text(controller.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !controller.pairingCode.isEmpty {
                VStack(spacing: 8) {
                    Text("Pairing code").font(.headline)
                    Text(controller.pairingCode)
                        .font(.system(size: 38, weight: .bold, design: .monospaced))
                        .tracking(8)
                        .accessibilityLabel("Six digit pairing code \(controller.pairingCode)")
                    Button("I confirm the codes match") { controller.confirmPairing() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if !controller.receivedText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Received sanitized preview").font(.headline)
                    TextEditor(text: .constant(controller.receivedText))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 130)
                        .disabled(true)
                    HStack {
                        Button("Copy Sanitized") { controller.copyReceived() }
                            .buttonStyle(.borderedProminent)
                        Button("Clear") { controller.clearReceived() }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Nearby ClipGum devices").font(.headline)
                        Spacer()
                        Text("\(controller.devices.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if controller.devices.isEmpty {
                        Label("No devices discovered yet. Keep this window open only while pairing.", systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        List(controller.devices) { device in
                            Button {
                                controller.select(device)
                            } label: {
                                Label(device.name, systemImage: "laptopcomputer.and.iphone")
                            }
                            .disabled(controller.status == .connecting || controller.status == .awaitingPairing || controller.status == .ready)
                        }
                        .frame(minHeight: 120, maxHeight: 190)
                    }
                }
            }

            Text("No history is synchronized. Payloads are cleaned again before sending and after receipt. Nothing is written to a pasteboard automatically.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Close & Stop Local Discovery") { controller.close() }
            }
        }
        .padding(20)
        .frame(width: 570, height: 610)
    }
}
