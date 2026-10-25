import AppKit
import Foundation

enum RichTextWorkflowError: LocalizedError, Equatable, Sendable {
    case noReadableText
    case noRichText
    case invalidRTF
    case inputTooLarge
    case serializationFailed

    var errorDescription: String? {
        switch self {
        case .noReadableText:
            return "The captured item has no readable plain-text, HTML, or RTF content."
        case .noRichText:
            return "Rich Text Sanitizer requires an HTML or RTF clipboard flavor."
        case .invalidRTF:
            return "The captured RTF flavor could not be decoded. No output was exported."
        case .inputTooLarge:
            return "RTF input exceeds the 4 MiB Office safety boundary."
        case .serializationFailed:
            return "AppKit could not serialize the sanitized document. No partial rich output was exported."
        }
    }
}

struct RichTextSanitizationResult: Equatable, Sendable {
    let plainText: String
    let sanitizedHTML: String
    let payload: PasteboardPayload
}

struct RichTextSanitizer {
    private let processor = HTMLSemanticProcessor()
    private let serializer = AppKitRichTextSerializer()

    func plainText(from document: PasteboardDocument) throws -> String {
        if let plainText = document.plainText, !plainText.isEmpty {
            return plainText
        }
        if let html = document.html, !html.isEmpty {
            let text = try processor.plainText(from: html)
            if !text.isEmpty { return text }
        }
        if let rtfData = document.rtfData {
            let attributed = try serializer.attributedString(fromRTF: rtfData)
            if !attributed.string.isEmpty { return attributed.string }
        }
        throw RichTextWorkflowError.noReadableText
    }

    func sanitize(document: PasteboardDocument) throws -> RichTextSanitizationResult {
        let sourceHTML: String
        if let html = document.html, !html.isEmpty {
            sourceHTML = html
        } else if let rtfData = document.rtfData {
            sourceHTML = try serializer.htmlFromRTF(rtfData)
        } else {
            throw RichTextWorkflowError.noRichText
        }

        let sanitizedHTML = try processor.sanitizedHTML(from: sourceHTML)
        let plainText = try plainText(from: document)
        let payload = try serializer.payload(
            plainText: plainText,
            sanitizedHTML: sanitizedHTML
        )
        return RichTextSanitizationResult(
            plainText: plainText,
            sanitizedHTML: sanitizedHTML,
            payload: payload
        )
    }
}

/// AppKit owns RTF/HTML attributed-string conversion; the semantic allowlist is
/// applied before any sanitized HTML reaches this serializer or the pasteboard.
struct AppKitRichTextSerializer {
    func attributedString(fromRTF data: Data) throws -> NSAttributedString {
        guard data.count <= HTMLScanner.maximumInputUTF8Bytes else {
            throw RichTextWorkflowError.inputTooLarge
        }
        guard let attributed = NSAttributedString(rtf: data, documentAttributes: nil) else {
            throw RichTextWorkflowError.invalidRTF
        }
        return attributed
    }

    func htmlFromRTF(_ data: Data) throws -> String {
        let attributed = try attributedString(fromRTF: data)
        do {
            let htmlData = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ]
            )
            guard let html = String(data: htmlData, encoding: .utf8) else {
                throw RichTextWorkflowError.serializationFailed
            }
            return html
        } catch let error as RichTextWorkflowError {
            throw error
        } catch {
            throw RichTextWorkflowError.serializationFailed
        }
    }

    func payload(plainText: String, sanitizedHTML: String) throws -> PasteboardPayload {
        let wrappedHTML = """
        <!DOCTYPE html><html><head><meta charset="utf-8"></head><body>\(sanitizedHTML)</body></html>
        """
        do {
            let attributed = try NSAttributedString(
                data: Data(wrappedHTML.utf8),
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )
            let rtfData = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            return PasteboardPayload(
                plainText: plainText,
                html: sanitizedHTML,
                rtfData: rtfData
            )
        } catch {
            throw RichTextWorkflowError.serializationFailed
        }
    }
}
