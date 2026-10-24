import Foundation

/// The only remote URL policy accepted by ClipGum's update and explicit model
/// acquisition features. Clipboard content never crosses this boundary.
enum HTTPSURLPolicy {
    static func isValid(_ url: URL?) -> Bool {
        guard
            let url,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "https",
            let host = components.host,
            !host.isEmpty,
            components.user == nil,
            components.password == nil
        else {
            return false
        }
        return true
    }

    static func isValid(string: String?) -> Bool {
        guard let string, let url = URL(string: string) else {
            return false
        }
        return isValid(url)
    }
}
