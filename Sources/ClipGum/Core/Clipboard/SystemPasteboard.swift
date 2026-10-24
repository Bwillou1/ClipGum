import AppKit
import Foundation

enum PasteboardReadResult: Equatable {
    case text(String)
    case accessDenied
    case excluded(marker: String)
    case noText
    case emptyText
    case multipleItems
}

enum PasteboardError: LocalizedError {
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .writeFailed:
            return "macOS did not accept the pasteboard write."
        }
    }
}

/// The only gateway to NSPasteboard used by the app.
///
/// There is deliberately no changeCount observer, timer, or polling API here.
struct SystemPasteboard {
    let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Reads one plain-text item only while handling an explicit user action.
    /// All available marker metadata is inspected before reading a string value.
    @MainActor
    func readTextForExplicitUserAction() -> PasteboardReadResult {
        if #available(macOS 15.4, *) {
            guard PasteboardAccessPolicy.allowsUserInitiatedRead(
                rawValue: pasteboard.accessBehavior.rawValue
            ) else {
                return .accessDenied
            }
        }

        let advertisedTypes = Set(pasteboard.types?.map(\.rawValue) ?? [])
        if let marker = PasteboardTypePolicy.firstIgnoredMarker(in: advertisedTypes) {
            return .excluded(marker: marker)
        }

        let items = pasteboard.pasteboardItems ?? []
        let itemTypes = Set(items.flatMap { item in
            item.types.map(\.rawValue)
        })
        if let marker = PasteboardTypePolicy.firstIgnoredMarker(in: itemTypes) {
            return .excluded(marker: marker)
        }

        guard items.count <= 1 else {
            return .multipleItems
        }
        guard let item = items.first else {
            return .noText
        }
        guard item.types.contains(.string), let text = item.string(forType: .string) else {
            return .noText
        }
        guard !text.isEmpty else {
            return .emptyText
        }

        return .text(text)
    }

    /// Every caller must name the explicit action that authorized this write.
    @MainActor
    func writeTextForExplicitUserAction(_ text: String) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw PasteboardError.writeFailed
        }
    }
}
