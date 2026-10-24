import Foundation

enum ChainCopyDelimiter: String, CaseIterable, Identifiable, Sendable {
    case newline
    case comma
    case markdownBullets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newline: return "Newline"
        case .comma: return "Comma"
        case .markdownBullets: return "Markdown bullets"
        }
    }
}

enum ChainCopyMoveDirection: Equatable, Sendable {
    case up
    case down
}

enum ChainCopyAddResult: Equatable, Sendable {
    case added
    case duplicate
    case empty
    case inactive
}

struct ChainCopyItem: Equatable, Identifiable, Sendable {
    let id: Int
    let text: String
    var isIncluded: Bool
}

/// Opt-in, volatile accumulator. Starting a chain and every addition require an
/// explicit clipboard invocation in the app layer. This type performs no I/O.
struct ChainCopySession: Equatable, Sendable {
    private(set) var items: [ChainCopyItem] = []
    private(set) var delimiter: ChainCopyDelimiter = .newline
    private(set) var isActive = false
    private var nextIdentifier = 1

    var combinedPreview: String {
        let selected = items.filter(\.isIncluded).map(\.text)
        switch delimiter {
        case .newline:
            return selected.joined(separator: "\n")
        case .comma:
            return selected.joined(separator: ",")
        case .markdownBullets:
            return selected.map { "- " + $0 }.joined(separator: "\n")
        }
    }

    @discardableResult
    mutating func start(with text: String) -> ChainCopyAddResult {
        self = ChainCopySession()
        isActive = true
        return add(text)
    }

    @discardableResult
    mutating func add(_ text: String) -> ChainCopyAddResult {
        guard isActive else { return .inactive }
        guard !text.isEmpty else { return .empty }
        guard !items.contains(where: { $0.text == text }) else { return .duplicate }
        items.append(ChainCopyItem(id: nextIdentifier, text: text, isIncluded: true))
        nextIdentifier += 1
        return .added
    }

    mutating func toggleInclusion(id: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isIncluded.toggle()
    }

    mutating func setAllIncluded(_ included: Bool) {
        for index in items.indices {
            items[index].isIncluded = included
        }
    }

    mutating func move(id: Int, direction: ChainCopyMoveDirection) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let destination: Int
        switch direction {
        case .up:
            guard index > items.startIndex else { return }
            destination = index - 1
        case .down:
            guard index < items.index(before: items.endIndex) else { return }
            destination = index + 1
        }
        items.swapAt(index, destination)
    }

    mutating func setDelimiter(_ delimiter: ChainCopyDelimiter) {
        self.delimiter = delimiter
    }

    mutating func clear() {
        self = ChainCopySession()
    }
}
