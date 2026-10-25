import AppKit
import SwiftUI

@MainActor
struct UpdateSettingsView: View {
    @ObservedObject var manager: UpdateManager

    var body: some View {
        Form {
            Section("Signed updates") {
                LabeledContent("Channel") {
                    Picker("Channel", selection: $manager.channel) {
                        ForEach(UpdateChannel.allCases) { channel in
                            Text(channel.title).tag(channel)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                Text("Stable receives default-channel releases. Beta also receives explicitly tagged beta items; it never enables a wildcard channel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Check for Updates") { manager.checkForUpdates() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!manager.isConfigured || !manager.canCheckForUpdates)
                Text(manager.availabilityMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Automatic checks") {
                Toggle("Check for updates automatically", isOn: $manager.automaticChecksEnabled)
                    .disabled(!manager.isConfigured)
                Picker("Frequency", selection: $manager.checkFrequency) {
                    ForEach(UpdateCheckFrequency.allCases) { frequency in
                        Text(frequency.title).tag(frequency)
                    }
                }
                .disabled(!manager.isConfigured || !manager.automaticChecksEnabled)
                Text("Automatic checks are off by default. Updates are never installed silently; Sparkle still asks before installation. No system-profile fields or extra feed parameters are sent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Release notes") {
                if let notes = manager.releaseNotes {
                    LabeledContent("Version", value: notes.version)
                    if !notes.plainText.isEmpty {
                        ScrollView {
                            Text(notes.plainText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 180)
                    }
                    if let url = notes.externalURL {
                        Button("Open Full Release Notes") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } else {
                    Text("After a signed update is found, its sanitized notes appear here and in Sparkle's release-notes window.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(18)
    }
}
