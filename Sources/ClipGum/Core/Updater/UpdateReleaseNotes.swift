import Foundation
import Sparkle

struct UpdateReleaseNotes: Equatable {
    let version: String
    let plainText: String
    let externalURL: URL?

    init?(item: SUAppcastItem) {
        version = item.displayVersionString
        if let description = item.itemDescription,
            description.utf8.count <= 512_000
        {
            plainText = (try? HTMLSemanticProcessor().plainText(from: description)) ?? ""
        } else {
            plainText = ""
        }
        externalURL = HTTPSURLPolicy.isValid(item.releaseNotesURL) ? item.releaseNotesURL : nil
        if plainText.isEmpty, externalURL == nil {
            return nil
        }
    }
}
