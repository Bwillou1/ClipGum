import AppKit
import SwiftUI

@MainActor
struct LiveInspectorView: View {
    @ObservedObject var engine = LiveInspectorEngine.shared
    @State private var copyFeedback = false

    private let categories = ["Tous", "Secrets", "URLs", "Tableaux", "IA"]

    var body: some View {
        VStack(spacing: 0) {
            // Header stats bar
            HStack(spacing: 16) {
                metricCard(
                    title: "Événements",
                    value: "\(engine.entries.count)",
                    icon: "bolt.fill",
                    color: .blue
                )
                metricCard(
                    title: "Secrets Neutralisés",
                    value: "\(engine.totalSecretsRedacted)",
                    icon: "lock.shield.fill",
                    color: .pink
                )
                metricCard(
                    title: "Traqueurs Purgés",
                    value: "\(engine.totalTrackersRemoved)",
                    icon: "link.badge.plus",
                    color: .cyan
                )
                metricCard(
                    title: "Latence Moyenne",
                    value: String(format: "%.1f ms", engine.averageLatencyMs),
                    icon: "stopwatch.fill",
                    color: .green
                )
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Filter & Search Controls
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filtrer les entrées du presse-papiers…", text: $engine.filterQuery)
                        .textFieldStyle(.plain)
                    if !engine.filterQuery.isEmpty {
                        Button {
                            engine.filterQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Picker("", selection: $engine.selectedCategory) {
                    ForEach(categories, id: \.self) { cat in
                        Text(cat).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Spacer()

                Button {
                    copyLogsToClipboard()
                } label: {
                    Label(copyFeedback ? "Copié !" : "Copier", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button {
                    engine.clear()
                } label: {
                    Label("Effacer", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))

            Divider()

            // Live event table
            if engine.filteredEntries.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                    Text("Aucun événement de collage capturé pour le moment.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Copiez du texte ou un lien dans une app et appuyez sur ⌘⇧V ou ⌘⌥V pour voir l'inspection en direct.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(engine.filteredEntries) { entry in
                        logRow(entry)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func logRow(_ entry: LiveInspectorLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(entry.timestampFormatted)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Text(entry.trigger)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())

                Text(entry.contentType)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.15))
                    .foregroundStyle(.purple)
                    .clipShape(Capsule())

                if entry.secretsRedacted > 0 {
                    Text("\(entry.secretsRedacted) Secret(s) masqué(s)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.pink.opacity(0.2))
                        .foregroundStyle(.pink)
                        .clipShape(Capsule())
                }

                if entry.trackersRemoved > 0 {
                    Text("\(entry.trackersRemoved) Traqueur(s)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.2))
                        .foregroundStyle(.cyan)
                        .clipShape(Capsule())
                }

                Spacer()

                Text(String(format: "%.1f ms", entry.latencyMs))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.green)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Original:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(entry.originalSnippet)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                        .foregroundStyle(.red.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Nettoyé (\(entry.actionName)):")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(entry.cleanedSnippet)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    private func copyLogsToClipboard() {
        let dump = engine.entries.map {
            "[\($0.timestampFormatted)] (\($0.trigger)) \($0.contentType) -> \($0.actionName) (\($0.latencyMs)ms)\nAvant: \($0.originalSnippet)\nAprès: \($0.cleanedSnippet)"
        }.joined(separator: "\n---\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(dump, forType: .string)
        copyFeedback = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copyFeedback = false
        }
    }
}
