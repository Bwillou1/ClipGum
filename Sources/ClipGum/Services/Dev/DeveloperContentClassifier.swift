import Foundation

enum DeveloperContentKind: Equatable, Sendable {
    case general
    case json
    case shell
    case stackTrace
}

struct DeveloperContentClassifier {
    private static let stackMarker = try! NSRegularExpression(
        pattern: #"(?im)^\s*(?:Traceback \(most recent call last\):|Exception in thread|fatal error:|panic:|at\s+(?:.*\(.*\)|\S+:\d+(?::\d+)?)|\s*File\s+\".+\",\s+line\s+\d+)"#
    )
    private static let shellCommand = try! NSRegularExpression(
        pattern: #"(?im)^\s*(?:#!(?:\S*/)?(?:ba|z|k)?sh\b|(?:sudo|doas|pkexec|rm|dd|mkfs(?:\.[a-z0-9]+)?|curl|wget|bash|sh|zsh|ksh|git|cd|ls|echo|printf|export|brew|npm|npx|pip|python3?|docker|kubectl|chmod|chown|mv|cp|mkdir|cat|grep|awk|sed|xargs|kill|launchctl|systemctl)(?:\s|$))"#
    )
    private static let logMarker = try! NSRegularExpression(
        pattern: #"(?m)^\s*(?:\[(?:\d{4}-\d{2}-\d{2}[T ])?\d{2}:\d{2}:\d{2}|\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}|\d{2}:\d{2}:\d{2}|[A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})"#
    )

    func classify(_ input: String) -> DeveloperContentKind {
        if JSONParser.validate(input).isValid {
            return .json
        }
        let range = NSRange(input.startIndex..., in: input)
        if Self.stackMarker.numberOfMatches(in: input, range: range) >= 2
            || input.contains("Traceback (most recent call last):")
            || input.contains("Exception in thread")
        {
            return .stackTrace
        }
        if Self.shellCommand.firstMatch(in: input, range: range) != nil
            || (input.contains(":(){")
                && BashInspector().inspect(input).findings.contains(where: { $0.code == .forkBomb }))
        {
            return .shell
        }
        if Self.logMarker.firstMatch(in: input, range: range) != nil
            || input.contains("\u{1B}[")
        {
            return .stackTrace
        }
        return .general
    }

    func actions(
        for input: String,
        hasRichText: Bool = false,
        hasTable: Bool = false
    ) -> [SmartPasteAction] {
        var actions: [SmartPasteAction] = [.clean]
        if hasRichText { actions.append(.sanitizeRichText) }
        actions.append(contentsOf: [.urlClean, .secretScrub, .shareReady, .restoreIdentifiers])
        let kind = classify(input)
        if kind == .general { actions.append(.repairPDF) }
        if hasTable { actions.append(.convertTable) }
        switch kind {
        case .json:
            actions.append(contentsOf: [.formatJSON, .minifyJSON, .jsonToTypeScript])
        case .shell:
            actions.append(contentsOf: [.inspectBash, .explainBash])
        case .stackTrace:
            actions.append(.scrubLogs)
        case .general:
            break
        }
        actions.append(contentsOf: [
            .correction, .professionalEmail, .rewrite, .slackSummary, .tableToCSV
        ])
        return actions
    }
}
