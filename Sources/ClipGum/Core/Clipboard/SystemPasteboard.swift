import AppKit
import Foundation

enum PasteboardReadResult: Equatable {
    case text(String)
    case document(PasteboardDocument)
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

    /// Compatibility API for plain-text callers. The app uses the document API
    /// below so HTML/RTF-only items have the same explicit-read safeguards.
    @MainActor
    func readTextForExplicitUserAction() -> PasteboardReadResult {
        switch readDocumentForExplicitUserAction() {
        case .document(let document):
            guard let text = document.plainText else { return .noText }
            guard !text.isEmpty else { return .emptyText }
            return .text(text)
        case .text(let text):
            return .text(text)
        case .accessDenied:
            return .accessDenied
        case .excluded(let marker):
            return .excluded(marker: marker)
        case .noText:
            return .noText
        case .emptyText:
            return .emptyText
        case .multipleItems:
            return .multipleItems
        }
    }

    /// Reads one item's plain text, public.html, and public.rtf flavors only
    /// while handling an explicit user action. All marker metadata is inspected
    /// before any flavor value is read.
    @MainActor
    func readDocumentForExplicitUserAction() -> PasteboardReadResult {
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

        let types = Set(item.types)
        guard !types.isDisjoint(with: [.string, .html, .rtf]) else {
            return .noText
        }
        let plainText = types.contains(.string) ? item.string(forType: .string) : nil
        let html = types.contains(.html) ? flavorString(for: .html, from: item) : nil
        let rtfData = types.contains(.rtf) ? item.data(forType: .rtf) : nil

        if plainText == nil && html == nil && rtfData == nil {
            return .noText
        }
        if plainText?.isEmpty != false, html?.isEmpty != false, rtfData == nil {
            return .emptyText
        }
        return .document(PasteboardDocument(
            plainText: plainText,
            html: html,
            rtfData: rtfData
        ))
    }

    /// Every caller must name the explicit action that authorized this write.
    @MainActor
    func writeTextForExplicitUserAction(_ text: String) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw PasteboardError.writeFailed
        }
    }

    /// Builds and validates one item before clearing the pasteboard, then writes
    /// plain text, sanitized HTML, and RTF together for Office targets.
    @MainActor
    func writeDocumentForExplicitUserAction(_ payload: PasteboardPayload) throws {
        let item = NSPasteboardItem()
        guard item.setString(payload.plainText, forType: .string) else {
            throw PasteboardError.writeFailed
        }
        if let html = payload.html {
            guard item.setString(html, forType: .html) else {
                throw PasteboardError.writeFailed
            }
        }
        if let rtfData = payload.rtfData {
            guard item.setData(rtfData, forType: .rtf) else {
                throw PasteboardError.writeFailed
            }
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw PasteboardError.writeFailed
        }
    }

    private func flavorString(
        for type: NSPasteboard.PasteboardType,
        from item: NSPasteboardItem
    ) -> String? {
        if let string = item.string(forType: type) {
            return string
        }
        guard let data = item.data(forType: type) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
