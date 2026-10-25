import ArgumentParser
import ClipGumCore
import Foundation

private enum CLIError: LocalizedError {
    case invalidUTF8
    case inputTooLarge
    case conflictingOutputFlags

    var errorDescription: String? {
        switch self {
        case .invalidUTF8: return "Input must be valid UTF-8 text."
        case .inputTooLarge: return "Input exceeds the 64 MiB CLI safety boundary."
        case .conflictingOutputFlags: return "--json and --diff cannot be used together."
        }
    }
}

private struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "Do not append a trailing newline to raw text output.")
    var raw = false

    @Flag(name: .long, help: "Emit a unified text diff instead of transformed text.")
    var diff = false

    @Flag(name: .long, help: "Emit a JSON object containing output and change count.")
    var json = false

    @Option(name: .long, help: "Locale override for locale-aware future operations; current transforms are locale invariant.")
    var locale: String?

    @Argument(help: "UTF-8 input file, or '-' / omitted for streamed standard input.")
    var input: String?

    mutating func validate() throws {
        guard !json || !diff else { throw CLIError.conflictingOutputFlags }
        if let locale, locale.utf8.count > 64 { throw CLIError.invalidUTF8 }
    }

    func read() throws -> String {
        let data: Data
        if let input, input != "-" {
            // mappedIfSafe avoids eagerly copying regular files. Stdin cannot
            // be mmap'd, so it uses bounded chunks below instead.
            data = try Data(contentsOf: URL(fileURLWithPath: input), options: [.mappedIfSafe])
        } else {
            var streamed = Data()
            while true {
                let chunk = try FileHandle.standardInput.read(upToCount: 64 * 1_024)
                guard let chunk, !chunk.isEmpty else { break }
                streamed.append(chunk)
                guard streamed.count <= 64 * 1_024 * 1_024 else { throw CLIError.inputTooLarge }
            }
            data = streamed
        }
        guard data.count <= 64 * 1_024 * 1_024 else { throw CLIError.inputTooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw CLIError.invalidUTF8 }
        return text
    }

    func render(operation: String, original: String, result: CoreTransformResult) throws -> String {
        if json {
            let payload = CLIJSONPayload(
                operation: operation,
                output: result.output,
                changeCount: result.changeCount
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return String(decoding: try encoder.encode(payload), as: UTF8.self) + "\n"
        }
        if diff {
            return unifiedDiff(before: original, after: result.output)
        }
        return result.output + (raw ? "" : "\n")
    }
}

private struct CLIJSONPayload: Encodable {
    let operation: String
    let output: String
    let changeCount: Int
}

private func unifiedDiff(before: String, after: String) -> String {
    let oldLines = before.split(separator: "\n", omittingEmptySubsequences: false)
    let newLines = after.split(separator: "\n", omittingEmptySubsequences: false)
    var output = "--- input\n+++ output\n@@ -1,\(oldLines.count) +1,\(newLines.count) @@\n"
    for line in oldLines { output += "-\(line)\n" }
    for line in newLines { output += "+\(line)\n" }
    return output
}

private func perform(
    _ operation: String,
    options: OutputOptions,
    transform: (String) throws -> CoreTransformResult
) throws {
    let input = try options.read()
    var result = try transform(input)
    // A managed ForceSecretRedaction policy applies to CLI output too. This is
    // deliberately after the transform and before stdout/pbcopy can receive it.
    if PolicyCenter().snapshot().forceSecretRedaction {
        let protected = DeterministicTransforms.redactSecrets(in: result.output)
        result = CoreTransformResult(
            output: protected.output,
            changeCount: result.changeCount + protected.changeCount
        )
    }
    let rendered = try options.render(operation: operation, original: input, result: result)
    try FileHandle.standardOutput.write(Data(rendered.utf8))
}

private struct CleanSecrets: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean-secrets",
        abstract: "Redact API keys, tokens, internal hosts, and IP addresses."
    )
    @OptionGroup var options: OutputOptions
    mutating func run() throws {
        try perform("clean-secrets", options: options) {
            DeterministicTransforms.redactSecrets(in: $0)
        }
    }
}

private struct SanitizeText: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sanitize-text",
        abstract: "Strip URL tracking parameters and redact secrets deterministically."
    )
    @OptionGroup var options: OutputOptions
    mutating func run() throws {
        try perform("sanitize-text", options: options) {
            DeterministicTransforms.sanitize($0)
        }
    }
}

private struct StripURLs: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "strip-urls",
        abstract: "Remove known tracking query parameters without rebuilding unrelated URL bytes."
    )
    @OptionGroup var options: OutputOptions
    mutating func run() throws {
        try perform("strip-urls", options: options) {
            DeterministicTransforms.stripTrackingParameters(in: $0)
        }
    }
}

private struct JSONToTS: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "json-to-ts",
        abstract: "Infer a deterministic TypeScript type from a JSON value."
    )
    @OptionGroup var options: OutputOptions
    @Option(name: .long, help: "TypeScript root identifier (default: Root).")
    var rootName = "Root"

    mutating func run() throws {
        try perform("json-to-ts", options: options) { input in
            let generated = try DeterministicTransforms.jsonToTypeScript(input, rootName: rootName)
            return CoreTransformResult(output: generated, changeCount: generated == input ? 0 : 1)
        }
    }
}

private struct ExtractTable: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "extract-table",
        abstract: "Normalize an RFC-4180-style CSV, TSV, or semicolon table to CSV."
    )
    @OptionGroup var options: OutputOptions
    mutating func run() throws {
        try perform("extract-table", options: options) {
            CoreTransformResult(output: try DeterministicTransforms.extractTable($0), changeCount: 1)
        }
    }
}

@main
struct ClipGumCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clipgum",
        abstract: "Air-gapped deterministic text tools for ClipGum.",
        subcommands: [CleanSecrets.self, SanitizeText.self, StripURLs.self, JSONToTS.self, ExtractTable.self]
    )
}
