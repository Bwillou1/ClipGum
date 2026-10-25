import Combine
import Foundation

enum PaletteAction {
    case runTransformation(SmartPasteAction)
    case restoreDeterministic
    case pasteCleaned
    case copyResult
    case pasteOriginal
    case clearShareReady
    case startChain
    case chainToggle(Int)
    case chainMove(Int, ChainCopyMoveDirection)
    case chainSelectAll(Bool)
    case chainDelimiter(ChainCopyDelimiter)
    case chainCopy
    case chainClear
    case openPasteboardPrivacySettings
    case cancel
}

struct PaletteMessage {
    let title: String
    let detail: String
    let systemImage: String
    let showsPrivacySettings: Bool

    init(
        title: String,
        detail: String,
        systemImage: String = "lock.shield",
        showsPrivacySettings: Bool = false
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.showsPrivacySettings = showsPrivacySettings
    }
}

enum PalettePreviewPhase: Equatable, Sendable {
    case deterministic
    case streaming
    case completed
}

struct PalettePreview: Equatable, Sendable {
    let original: String
    let deterministicBaseline: CleaningResult
    var action: SmartPasteAction
    var output: String
    var phase: PalettePreviewPhase
    var validation: ValidationReport?
    var streamedChunks: Int
    var errorMessage: String?
    var pasteboardPayload: PasteboardPayload?

    init(
        deterministicResult: CleaningResult,
        action: SmartPasteAction = .clean,
        errorMessage: String? = nil
    ) {
        original = deterministicResult.original
        deterministicBaseline = deterministicResult
        self.action = action
        output = deterministicResult.cleaned
        phase = .deterministic
        validation = nil
        streamedChunks = 0
        self.errorMessage = errorMessage
        pasteboardPayload = deterministicResult.pasteboardPayload
    }

    var exportPayload: PasteboardPayload? {
        guard let pasteboardPayload, pasteboardPayload.plainText == output else { return nil }
        return pasteboardPayload
    }

    var isStreaming: Bool {
        phase == .streaming
    }

    var canExport: Bool {
        guard !output.isEmpty else {
            return false
        }
        switch phase {
        case .deterministic:
            return true
        case .streaming:
            return false
        case .completed:
            return validation?.canExport == true
        }
    }
}

enum PaletteContent {
    case preview(PalettePreview)
    case chain(ChainCopySession)
    case message(PaletteMessage)

    var panelSize: (width: CGFloat, height: CGFloat) {
        switch self {
        case .preview:
            return (1_000, 720)
        case .chain:
            return (920, 720)
        case .message:
            return (540, 280)
        }
    }
}

enum PaletteDiffMode: String, CaseIterable, Identifiable {
    case sideBySide
    case inline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sideBySide: return "Before / After"
        case .inline: return "Inline Diff"
        }
    }
}

@MainActor
final class PaletteModel: ObservableObject {
    @Published var content: PaletteContent
    @Published var selectedAction: SmartPasteAction = .clean
    @Published var diffMode: PaletteDiffMode = .sideBySide
    @Published var jsonIndentation: JSONIndentation = .twoSpaces
    @Published var typeScriptRootName = "Root"
    @Published var typeScriptIncludesExport = true
    @Published var tableFormat: TableOutputFormat = .csv
    @Published var tableDelimiter: TableDelimiter = .comma
    @Published var shareReadyMappingCount = 0
    @Published var managedPolicyBadges: [String] = []

    let availableActions: [SmartPasteAction]
    let suggestedActions: [SmartPasteAction]
    let bashInspection: BashInspection?
    let tableDetection: TableDetection?
    let appProfile: OfficeAppProfile?

    var developerOptions: DeveloperActionOptions {
        DeveloperActionOptions(
            jsonIndentation: jsonIndentation,
            typeScriptRootName: typeScriptRootName,
            typeScriptIncludesExport: typeScriptIncludesExport,
            table: TableConversionOptions(format: tableFormat, delimiter: tableDelimiter)
        )
    }

    init(
        content: PaletteContent,
        document: PasteboardDocument? = nil,
        appProfile: OfficeAppProfile? = nil
    ) {
        self.content = content
        self.appProfile = appProfile
        if case .preview(let preview) = content {
            let classifier = DeveloperContentClassifier()
            let detection = TableExtractionService().detect(
                document: document,
                plainText: preview.original
            )
            tableDetection = detection
            let actions = classifier.actions(
                for: preview.original,
                hasRichText: document?.hasRichFlavor ?? false,
                hasTable: detection != nil
            )
            availableActions = actions
            suggestedActions = (appProfile?.suggestedActions ?? []).filter {
                actions.contains($0)
            }
            if classifier.classify(preview.original) == .shell {
                bashInspection = BashInspector().inspect(preview.original)
            } else {
                bashInspection = nil
            }
        } else {
            availableActions = []
            suggestedActions = []
            bashInspection = nil
            tableDetection = nil
        }
    }
}
