import Foundation

/// Session-only access granted by NSOpenPanel. No bookmark or model path is persisted.
final class SecurityScopedModelAccess {
    let url: URL
    private let didStartAccessing: Bool

    init(url: URL) {
        self.url = url
        didStartAccessing = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if didStartAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
