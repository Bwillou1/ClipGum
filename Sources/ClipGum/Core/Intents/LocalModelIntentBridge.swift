import Foundation

public enum LocalModelIntentError: LocalizedError {
    case modelUnavailable
    case emptyOutput

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable: return "Select and load a local model in ClipGum before running this Shortcut."
        case .emptyOutput: return "The local model returned no approved output."
        }
    }
}

/// Async, UI-free bridge installed by the app after launch. The intent module
/// does not retain an AppDelegate, window, pasteboard, or SwiftUI object.
actor LocalModelIntentBridge {
    static let shared = LocalModelIntentBridge()
    typealias Handler = @Sendable (String) async throws -> String
    private var handler: Handler?

    func install(_ handler: @escaping Handler) {
        self.handler = handler
    }

    func transform(_ input: String) async throws -> String {
        guard let handler else { throw LocalModelIntentError.modelUnavailable }
        return try await handler(input)
    }
}
