import Foundation

/// One explicitly captured pasteboard item. Values are read only after the
/// existing access and sensitive-marker gates have succeeded.
struct PasteboardDocument: Equatable, Sendable {
    let plainText: String?
    let html: String?
    let rtfData: Data?

    init(plainText: String? = nil, html: String? = nil, rtfData: Data? = nil) {
        self.plainText = plainText
        self.html = html
        self.rtfData = rtfData
    }

    var hasRichFlavor: Bool {
        html != nil || rtfData != nil
    }
}

/// Validated flavors for one explicit write. Plain text is always present as a
/// compatibility fallback; rich flavors are optional and remain in one item.
struct PasteboardPayload: Equatable, Sendable {
    let plainText: String
    let html: String?
    let rtfData: Data?

    init(plainText: String, html: String? = nil, rtfData: Data? = nil) {
        self.plainText = plainText
        self.html = html
        self.rtfData = rtfData
    }
}
