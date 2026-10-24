import SwiftUI

@MainActor
struct PaletteView: View {
    @ObservedObject var model: PaletteModel
    let onAction: (PaletteAction) -> Void

    private enum DiffPerspective {
        case before
        case after
        case inline
    }

    var body: some View {
        Group {
            switch model.content {
            case .preview(let preview):
                previewView(preview)
            case .chain(let session):
                chainView(session)
            case .message(let message):
                messageView(message)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
        .padding(1)
    }

    private func previewView(_ preview: PalettePreview) -> some View {
        let diff = InlineDiff.segments(before: preview.original, after: preview.output)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: preview.isStreaming ? "sparkles" : "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Smart Paste")
                        .font(.headline)
                    Text("On-demand · Local only · Original kept in memory")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let inspection = model.bashInspection, inspection.isDangerous {
                    Label("DANGER · \(inspection.findings.count)", systemImage: "exclamationmark.octagon.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .accessibilityLabel("Dangerous shell command. \(inspection.findings.count) safety findings.")
                }
                if preview.validation?.hasDataInvariantFailure == true {
                    Label("DATA DISCREPANCY · EXPORT BLOCKED", systemImage: "exclamationmark.octagon.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
                statusBadge(preview)
            }

            HStack(spacing: 9) {
                Picker("Action", selection: $model.selectedAction) {
                    ForEach(model.availableActions) { action in
                        Text(action.title).tag(action)
                    }
                }
                .frame(maxWidth: 360)
                .disabled(preview.isStreaming)

                Button(preview.isStreaming ? "Generating…" : "Run") {
                    onAction(.runTransformation(model.selectedAction))
                }
                .buttonStyle(.borderedProminent)
                .disabled(preview.isStreaming)

                if preview.phase == .completed, !preview.canExport {
                    Button("Use Deterministic") {
                        onAction(.restoreDeterministic)
                    }
                }

                Spacer()
                Picker("Diff mode", selection: $model.diffMode) {
                    ForEach(PaletteDiffMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }
            .controlSize(.small)

            officeContextView
            developerOptionsView
            bashFindingsView

            if preview.isStreaming {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Local token stream · \(preview.streamedChunks) chunks")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Text("Provisional output — Copy/Paste disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            if let errorMessage = preview.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            validationView(preview)

            Group {
                switch model.diffMode {
                case .sideBySide:
                    HStack(spacing: 12) {
                        diffPane(title: "Before", diff: diff, perspective: .before)
                        diffPane(title: "After", diff: diff, perspective: .after)
                    }
                case .inline:
                    diffPane(
                        title: "Inline · red strikethrough removed · green underline added",
                        diff: diff,
                        perspective: .inline
                    )
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                summaryItem(
                    value: preview.deterministicBaseline.removedTrackingParameters,
                    singular: "tracking parameter",
                    plural: "tracking parameters"
                )
                summaryItem(
                    value: preview.deterministicBaseline.redactedSecrets,
                    singular: "potential secret",
                    plural: "potential secrets"
                )
                if model.shareReadyMappingCount > 0 {
                    Button("Clear Share-Ready (\(model.shareReadyMappingCount))") {
                        onAction(.clearShareReady)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.orange)
                }
                Spacer()
                Text("No model output is approved before validation.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(preview.exportPayload == nil
                ? "The pasteboard changes only after you choose Copy or Paste."
                : "Copy/Paste writes plain text, sanitized HTML, and RTF together as one pasteboard item."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Cancel", role: .cancel) {
                    onAction(.cancel)
                }
                Button("Chain Copy") {
                    onAction(.startChain)
                }
                .disabled(preview.isStreaming)
                Spacer()
                Button("Paste Original") {
                    onAction(.pasteOriginal)
                }
                Button("Copy Result") {
                    onAction(.copyResult)
                }
                .disabled(!preview.canExport)
                Button("Paste Cleaned") {
                    onAction(.pasteCleaned)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!preview.canExport)
            }
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var officeContextView: some View {
        if let profile = model.appProfile, !model.suggestedActions.isEmpty {
            HStack(spacing: 8) {
                Label(profile.displayName, systemImage: "app.badge")
                    .font(.caption.weight(.semibold))
                Text("Suggested:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(model.suggestedActions) { action in
                    Button(action.title) {
                        model.selectedAction = action
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
                Text("Metadata only · no extra clipboard read")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var developerOptionsView: some View {
        switch model.selectedAction {
        case .convertTable:
            VStack(alignment: .leading, spacing: 8) {
                if let detection = model.tableDetection {
                    Label(
                        "\(detection.source.title) · \(detection.rowCount) rows × \(detection.columnCount) columns",
                        systemImage: "tablecells"
                    )
                    .font(.caption.weight(.semibold))
                }
                HStack(spacing: 12) {
                    Picker("Table format", selection: $model.tableFormat) {
                        ForEach(TableOutputFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    Picker("CSV delimiter", selection: $model.tableDelimiter) {
                        ForEach(TableDelimiter.allCases) { delimiter in
                            Text(delimiter.title).tag(delimiter)
                        }
                    }
                    .frame(width: 190)
                    .disabled(model.tableFormat != .csv)
                    Text("Values remain unchanged; choose Run to refresh the preview.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        case .sanitizeRichText:
            Label(
                "Preserves bold, italics, links, H1–H3, and lists; strips CSS, backgrounds, and foreign typography. Export includes plain text, sanitized HTML, and AppKit RTF.",
                systemImage: "doc.richtext"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        case .repairPDF:
            Label(
                "Joins hard wraps and soft word-break hyphens while preserving blank-line paragraphs and accented text.",
                systemImage: "doc.plaintext"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .professionalEmail, .slackSummary:
            Label(
                "Numbers, dates, currency symbols, and formulas are checked after generation. Any discrepancy blocks export.",
                systemImage: "checkmark.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .formatJSON:
            HStack {
                Text("JSON indentation")
                    .font(.caption)
                Picker("Indent", selection: $model.jsonIndentation) {
                    ForEach(JSONIndentation.allCases) { indentation in
                        Text(indentation.title).tag(indentation)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                Spacer()
            }
        case .jsonToTypeScript:
            HStack(spacing: 12) {
                Text("Root name")
                    .font(.caption)
                TextField("Root", text: $model.typeScriptRootName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                Toggle("Export declarations", isOn: $model.typeScriptIncludesExport)
                    .font(.caption)
                Spacer()
            }
        case .shareReady, .restoreIdentifiers:
            Label(
                "Fictional ↔ real mappings are volatile RAM only. Clear them explicitly or on quit.",
                systemImage: "memorychip"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .inspectBash, .explainBash:
            Label(
                "Inspection only: no shell execution. Deterministic danger findings override model output.",
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var bashFindingsView: some View {
        if let inspection = model.bashInspection,
            inspection.isDangerous || inspection.parseError != nil
        {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(inspection.findings.prefix(4).enumerated()), id: \.offset) { _, finding in
                    Label(finding.title, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                if let parseError = inspection.parseError {
                    Label(parseError.message, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusBadge(_ preview: PalettePreview) -> some View {
        Group {
            if preview.isStreaming {
                Label("Streaming", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.tint)
            } else if preview.phase == .completed, preview.validation?.canExport == false {
                Label("Blocked", systemImage: "xmark.shield.fill")
                    .foregroundStyle(.red)
            } else if preview.phase == .completed, preview.validation?.warnings.isEmpty == false {
                Label("Review", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if preview.original != preview.output {
                Label("Changed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("No matching changes")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.semibold))
    }

    @ViewBuilder
    private func validationView(_ preview: PalettePreview) -> some View {
        if preview.phase == .completed, let validation = preview.validation {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(validation.issues.prefix(3).enumerated()), id: \.offset) { _, issue in
                    Label(
                        issue.message,
                        systemImage: issue.severity == .error
                            ? "xmark.octagon.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(issue.severity == .error ? .red : .orange)
                }
                if validation.issues.isEmpty {
                    Label(
                        preview.action == .tableToCSV
                            ? "CSV schema and every source cell verified."
                            : "Output checks passed; semantic review is still required.",
                        systemImage: "checkmark.circle"
                    )
                    .foregroundStyle(.green)
                }
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func diffPane(
        title: String,
        diff: [InlineDiffSegment],
        perspective: DiffPerspective
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            ScrollView {
                styledDiff(diff, perspective: perspective)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func styledDiff(
        _ segments: [InlineDiffSegment],
        perspective: DiffPerspective
    ) -> Text {
        var result = Text("")
        for segment in segments {
            switch (perspective, segment.kind) {
            case (_, .unchanged):
                result = result + Text(segment.text).foregroundColor(.primary)
            case (.before, .insertion):
                continue
            case (.after, .removal):
                continue
            case (_, .removal):
                result = result + Text(segment.text)
                    .foregroundColor(.red)
                    .strikethrough(true, color: .red)
            case (_, .insertion):
                result = result + Text(segment.text)
                    .foregroundColor(.green)
                    .underline(true, color: .green)
            }
        }
        return result
    }

    private func summaryItem(value: Int, singular: String, plural: String) -> some View {
        Text("\(value) \(value == 1 ? singular : plural)")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
    }

    private func chainView(_ session: ChainCopySession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "link.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chain Copy")
                        .font(.headline)
                    Text("Opt-in · Volatile · Exact duplicates ignored")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(session.items.count) clip\(session.items.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text("Copy the next selection, then invoke ⌘⇧V again. Each read requires that explicit invocation; ClipGum does not watch the pasteboard.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Picker("Join with", selection: Binding<ChainCopyDelimiter>(
                    get: { session.delimiter },
                    set: { onAction(.chainDelimiter($0)) }
                )) {
                    ForEach(ChainCopyDelimiter.allCases) { delimiter in
                        Text(delimiter.title).tag(delimiter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 480)
                Spacer()
                Button("Select all") { onAction(.chainSelectAll(true)) }
                Button("Select none") { onAction(.chainSelectAll(false)) }
            }
            .controlSize(.small)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CLIPS · TOGGLE / REORDER")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(session.items) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Button {
                                        onAction(.chainToggle(item.id))
                                    } label: {
                                        Image(systemName: item.isIncluded ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(item.isIncluded ? Color.accentColor : Color.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(item.isIncluded ? "Exclude clip" : "Include clip")
                                    Text(item.text)
                                        .font(.caption.monospaced())
                                        .lineLimit(4)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    VStack(spacing: 2) {
                                        Button {
                                            onAction(.chainMove(item.id, .up))
                                        } label: {
                                            Image(systemName: "chevron.up")
                                        }
                                        .disabled(session.items.first?.id == item.id)
                                        Button {
                                            onAction(.chainMove(item.id, .down))
                                        } label: {
                                            Image(systemName: "chevron.down")
                                        }
                                        .disabled(session.items.last?.id == item.id)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(8)
                                .background(Color.secondary.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            }
                        }
                        .padding(2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("LIVE COMBINED PREVIEW")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(session.combinedPreview.isEmpty
                            ? "Select at least one clip to build a preview."
                            : session.combinedPreview)
                            .font(.callout.monospaced())
                            .foregroundStyle(session.combinedPreview.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            Text("No clipboard write occurs while assembling or previewing this chain.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Clear Chain", role: .destructive) { onAction(.chainClear) }
                Button("Close & Continue") { onAction(.cancel) }
                Spacer()
                Button("Copy Combined & Clear") { onAction(.chainCopy) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(session.combinedPreview.isEmpty)
            }
            .controlSize(.large)
        }
    }

    private func messageView(_ message: PaletteMessage) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 12) {
                Image(systemName: message.systemImage)
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.title)
                        .font(.title3.weight(.semibold))
                    Text("Clipboard left untouched")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(message.detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack {
                if message.showsPrivacySettings {
                    Button("Cancel", role: .cancel) {
                        onAction(.cancel)
                    }
                    Spacer()
                    Button("Open Privacy Settings") {
                        onAction(.openPasteboardPrivacySettings)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Spacer()
                    Button("Close") {
                        onAction(.cancel)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
        }
    }
}
