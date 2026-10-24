import Foundation

enum BashRiskCode: String, Hashable, Sendable {
    case recursiveForcedRemoval
    case diskWriter
    case filesystemFormatter
    case forkBomb
    case downloadToShell
    case elevatedPrivileges
}

struct BashSafetyFinding: Equatable, Sendable {
    let code: BashRiskCode
    let title: String
    let detail: String
}

struct BashInspection: Equatable, Sendable {
    let tokens: [ShellToken]
    let findings: [BashSafetyFinding]
    let parseError: BashSyntaxError?

    var isDangerous: Bool { !findings.isEmpty }
}

/// Deterministic safety layer. LLM explanations are advisory and can never
/// downgrade or suppress these findings.
struct BashInspector {
    private let parser = BashCommandParser()

    func inspect(_ input: String) -> BashInspection {
        let parsed = parser.parse(input)
        var findings: [BashSafetyFinding] = []
        let segments = commandSegments(parsed.tokens)

        if isForkBomb(input) {
            findings.append(finding(
                .forkBomb,
                "Fork bomb detected",
                "This function recursively launches background copies and can exhaust the system."
            ))
        }
        for segment in segments {
            let executable = normalizedExecutable(segment.executable)
            if executable == "sudo" || executable == "doas" || executable == "pkexec" {
                findings.append(finding(
                    .elevatedPrivileges,
                    "Elevated privileges requested",
                    "The command asks for elevated privileges. ClipGum will never execute it."
                ))
            }
            let elevatedWords = ["sudo", "doas", "pkexec"].contains(executable)
            let candidates = elevatedWords
                ? segment.words.map { normalizedExecutable($0.text) }
                : [executable]
            if let rmIndex = candidates.firstIndex(of: "rm") {
                let flags = segment.words.dropFirst(rmIndex + 1).map(\.text)
                if hasRecursiveForcedRemoval(flags) {
                    findings.append(finding(
                        .recursiveForcedRemoval,
                        "Recursive forced deletion",
                        "rm with recursive and force flags can irreversibly delete entire directory trees."
                    ))
                }
            }
            if candidates.contains("dd") {
                findings.append(finding(
                    .diskWriter,
                    "Raw disk writer detected",
                    "dd can overwrite files, devices, partitions, or an entire boot disk."
                ))
            }
            if candidates.contains(where: { $0 == "mkfs" || $0.hasPrefix("mkfs.") || $0 == "mke2fs" }) {
                findings.append(finding(
                    .filesystemFormatter,
                    "Filesystem formatter detected",
                    "Filesystem creation or formatting destroys existing data on its target."
                ))
            }
        }
        if hasDownloadToShellPipeline(parsed.tokens) {
            findings.append(finding(
                .downloadToShell,
                "Download piped to a shell",
                "This runs network-delivered text as shell code without a reviewed artifact boundary."
            ))
        }
        return BashInspection(
            tokens: parsed.tokens,
            findings: uniqueFindings(findings),
            parseError: parsed.error
        )
    }

    func report(_ inspection: BashInspection) -> String {
        var lines = [
            "BASH INSPECTION — NOT EXECUTED",
            inspection.isDangerous
                ? "DANGER: \(inspection.findings.count) high-risk finding(s)."
                : "No covered high-risk pattern detected; manual review is still required."
        ]
        if let parseError = inspection.parseError {
            lines.append("Parse warning: \(parseError.message) (line \(parseError.line), column \(parseError.column))")
        }
        if !inspection.findings.isEmpty {
            lines.append("\nDeterministic safety findings:")
            lines.append(contentsOf: inspection.findings.map { "- \($0.title): \($0.detail)" })
        }
        let visibleTokens = inspection.tokens.filter { $0.kind != .comment }
        if !visibleTokens.isEmpty {
            lines.append("\nToken stream:")
            var commandPending = true
            for token in visibleTokens {
                switch token.kind {
                case .word:
                    let role = commandPending ? "command" : token.text.hasPrefix("-") ? "flag" : "parameter"
                    lines.append("- \(role): \(token.text)")
                    commandPending = false
                case .pipeline:
                    lines.append("- pipeline: \(token.text)")
                    commandPending = true
                case .conjunction:
                    lines.append("- conjunction: \(token.text)")
                    commandPending = true
                case .sequence:
                    lines.append("- separator: \(token.text == "\n" ? "newline" : token.text)")
                    commandPending = true
                case .redirect:
                    lines.append("- redirection: \(token.text)")
                case .otherOperator:
                    lines.append("- operator: \(token.text)")
                case .comment:
                    break
                }
            }
        }
        lines.append("\nExecution capability: disabled. No command was run or sent to a shell.")
        return lines.joined(separator: "\n")
    }

    private struct Segment {
        var words: [ShellToken]
        var executable: String
    }

    private func commandSegments(_ tokens: [ShellToken]) -> [Segment] {
        var segments: [Segment] = []
        var words: [ShellToken] = []
        var skipRedirectTarget = false

        func finish() {
            guard let executable = words.first(where: {
                !$0.text.contains("=") || $0.text.hasPrefix("-")
            })?.text else {
                words = []
                return
            }
            segments.append(Segment(words: words, executable: executable))
            words = []
        }

        for token in tokens {
            switch token.kind {
            case .pipeline, .conjunction, .sequence:
                finish()
                skipRedirectTarget = false
            case .redirect:
                skipRedirectTarget = true
            case .word:
                if skipRedirectTarget {
                    skipRedirectTarget = false
                } else {
                    words.append(token)
                }
            case .comment:
                break
            case .otherOperator:
                continue
            }
        }
        finish()
        return segments
    }

    private func normalizedExecutable(_ word: String) -> String {
        word.split(separator: "/", omittingEmptySubsequences: false).last.map {
            String($0).lowercased()
        } ?? ""
    }

    private func hasRecursiveForcedRemoval(_ flags: [String]) -> Bool {
        var recursive = false
        var forced = false
        for flag in flags where flag.hasPrefix("-") {
            if flag == "--recursive" || flag == "-R" {
                recursive = true
            }
            if flag == "--force" {
                forced = true
            }
            if flag.hasPrefix("-"), !flag.hasPrefix("--") {
                recursive = recursive || flag.dropFirst().contains("r") || flag.dropFirst().contains("R")
                forced = forced || flag.dropFirst().contains("f")
            }
        }
        return recursive && forced
    }

    private func hasDownloadToShellPipeline(_ tokens: [ShellToken]) -> Bool {
        var pipelineParts: [[String]] = [[]]
        for token in tokens {
            if token.kind == .pipeline {
                pipelineParts.append([])
            } else if token.kind == .conjunction || token.kind == .sequence {
                pipelineParts = [[]]
            } else if token.kind == .word {
                pipelineParts[pipelineParts.count - 1].append(token.text)
            }
        }
        guard pipelineParts.count > 1 else { return false }
        for index in 1..<pipelineParts.count {
            let left = normalizedExecutable(pipelineParts[index - 1].first ?? "")
            let rightWords = pipelineParts[index]
            let rightExecutable = normalizedExecutable(rightWords.first ?? "")
            let rightCandidates = ["sudo", "doas", "pkexec"].contains(rightExecutable)
                ? rightWords.map { normalizedExecutable($0) }
                : [rightExecutable]
            if ["curl", "wget"].contains(left),
                rightCandidates.contains(where: { ["bash", "sh", "zsh", "ksh"].contains($0) })
            {
                return true
            }
        }
        return false
    }

    private func isForkBomb(_ input: String) -> Bool {
        let compact = input.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        let text = compact.map(String.init).joined()
        return text.contains(":(){:|:&};:")
    }

    private func finding(_ code: BashRiskCode, _ title: String, _ detail: String) -> BashSafetyFinding {
        BashSafetyFinding(code: code, title: title, detail: detail)
    }

    private func uniqueFindings(_ findings: [BashSafetyFinding]) -> [BashSafetyFinding] {
        var seen: Set<BashRiskCode> = []
        return findings.filter { seen.insert($0.code).inserted }
    }
}
