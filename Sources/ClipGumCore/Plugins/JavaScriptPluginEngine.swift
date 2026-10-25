import Darwin
import Foundation
import JavaScriptCore

private final class JSCExecutionFlags {
    var failed = false
    var timedOut = false
    var memoryExceeded = false
    var memoryBefore: UInt64?
}

/// Resolves WebKit's exported context-group watchdog without making a private
/// header part of the target. The limiter is a runtime requirement: if it is
/// unavailable, ClipGum refuses to run user JavaScript rather than claiming a
/// timeout guarantee it cannot enforce.
private enum JSCWatchdog {
    private typealias TerminateCallback = @convention(c) (
        JSContextRef?, UnsafeMutableRawPointer?
    ) -> Bool
    private typealias SetLimitFunction = @convention(c) (
        JSContextGroupRef?, Double, TerminateCallback?, UnsafeMutableRawPointer?
    ) -> Void

    private static let setLimit: SetLimitFunction? = {
        guard let handle = dlopen(
            "/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore",
            RTLD_LAZY
        ), let symbol = dlsym(handle, "JSContextGroupSetExecutionTimeLimit") else {
            return nil
        }
        return unsafeBitCast(symbol, to: SetLimitFunction.self)
    }()

    static func install(on context: JSContext, flags: JSCExecutionFlags) -> Bool {
        guard let setLimit else { return false }
        let group = JSContextGetGroup(context.jsGlobalContextRef)
        let pointer = Unmanaged.passUnretained(flags).toOpaque()
        setLimit(group, 0.250, { _, rawFlags in
            guard let rawFlags else { return true }
            let flags = Unmanaged<JSCExecutionFlags>.fromOpaque(rawFlags).takeUnretainedValue()
            flags.timedOut = true
            if let before = flags.memoryBefore, let after = CoreProcessMemory.residentBytes(),
               after > before, after - before > JavaScriptPluginEngine.memoryBudgetBytes {
                flags.memoryExceeded = true
            }
            return true
        }, pointer)
        return true
    }
}

public struct JavaScriptPluginEngine {
    public static let executionBudgetMilliseconds = 250
    public static let memoryBudgetBytes = 16 * 1_024 * 1_024
    public static let maximumSourceBytes = 64 * 1_024
    public static let maximumInputBytes = 2 * 1_024 * 1_024
    public static let maximumOutputBytes = 2 * 1_024 * 1_024

    public init() {}

    /// Evaluates one self-contained Boop-compatible `main(input)` script.
    /// No native object, module loader, URL session, file handle, environment
    /// reader, or pasteboard object is injected into the context.
    public func evaluate(script: String, input: String) throws -> String {
        guard script.utf8.count <= Self.maximumSourceBytes else {
            throw CustomRuleError.sourceTooLarge
        }
        guard input.utf8.count <= Self.maximumInputBytes else {
            throw CustomRuleError.inputTooLarge
        }

        let flags = JSCExecutionFlags()
        guard let context = JSContext(), JSCWatchdog.install(on: context, flags: flags) else {
            throw CustomRuleError.watchdogUnavailable
        }
        context.exceptionHandler = { _, _ in
            flags.failed = true
        }

        // JavaScriptCore does not provide these host capabilities by default;
        // explicitly shadow common names as a second line of defense against
        // accidental future host bridges. Only the input argument crosses in.
        for name in [
            "require", "fetch", "XMLHttpRequest", "WebSocket", "Worker",
            "process", "console", "print", "load", "readFile", "writeFile",
            "FileManager", "NSFileManager", "NSPasteboard", "pasteboard",
            "ObjC", "AppleEvents", "system", "exec", "open"
        ] {
            context.setValue(nil, forKeyedSubscript: name as NSString)
        }

        flags.memoryBefore = CoreProcessMemory.residentBytes()
        _ = context.evaluateScript(script)
        if flags.memoryExceeded { throw CustomRuleError.memoryBudgetExceeded }
        if flags.timedOut { throw CustomRuleError.executionTimedOut }
        if flags.failed || context.exception != nil { throw CustomRuleError.scriptFailed }
        guard let main = context.objectForKeyedSubscript("main"), main.isFunction else {
            throw CustomRuleError.missingMainFunction
        }

        let value = main.call(withArguments: [input])
        if flags.memoryExceeded { throw CustomRuleError.memoryBudgetExceeded }
        if flags.timedOut { throw CustomRuleError.executionTimedOut }
        if flags.failed || context.exception != nil { throw CustomRuleError.scriptFailed }
        if let before = flags.memoryBefore, let after = CoreProcessMemory.residentBytes(),
           after > before, after - before > Self.memoryBudgetBytes {
            throw CustomRuleError.memoryBudgetExceeded
        }
        guard let value, value.isString, let output = value.toString() else {
            throw CustomRuleError.nonStringResult
        }
        guard output.utf8.count <= Self.maximumOutputBytes else {
            throw CustomRuleError.outputTooLarge
        }
        return output
    }
}

public struct CustomRuleEngine {
    public init() {}

    public func apply(
        _ input: String,
        rules: [CustomRule],
        allowScripts: Bool = true
    ) throws -> String {
        var output = input
        for rule in rules where rule.isEnabled {
            switch rule.kind {
            case .regex:
                output = try applyRegex(rule, to: output)
            case .script:
                guard allowScripts else { throw CustomRuleError.scriptDisabledByPolicy }
                output = try JavaScriptPluginEngine().evaluate(script: rule.source, input: output)
            }
            guard output.utf8.count <= JavaScriptPluginEngine.maximumOutputBytes else {
                throw CustomRuleError.outputTooLarge
            }
        }
        return output
    }

    private func applyRegex(_ rule: CustomRule, to input: String) throws -> String {
        guard rule.source.utf8.count <= 16 * 1_024 else { throw CustomRuleError.sourceTooLarge }
        let expression: NSRegularExpression
        do {
            expression = try NSRegularExpression(pattern: rule.source)
        } catch {
            throw CustomRuleError.invalidExpression
        }
        let result = expression.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: rule.replacement
        )
        return result
    }
}
