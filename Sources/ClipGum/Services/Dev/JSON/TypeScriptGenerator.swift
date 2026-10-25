import Foundation

struct TypeScriptGenerationOptions: Equatable, Sendable {
    var rootName: String = "Root"
    var includesExport = true
}

enum TypeScriptGenerationError: LocalizedError, Equatable, Sendable {
    case invalidRootName

    var errorDescription: String? {
        "Enter a non-reserved TypeScript identifier beginning with a letter, '_', or '$'."
    }
}

private struct InferredProperty: Equatable {
    let name: String
    var type: InferredType
    var isOptional: Bool
}

private struct InferredObject: Equatable {
    var properties: [InferredProperty]
}

private indirect enum InferredType: Equatable {
    case string
    case number
    case boolean
    case null
    case unknown
    case object(InferredObject)
    case array(InferredType)
    case union([InferredType])

    static func infer(_ value: JSONValue) -> InferredType {
        switch value {
        case .string: return .string
        case .number: return .number
        case .bool: return .boolean
        case .null: return .null
        case .array(let values):
            guard let first = values.first else { return .array(.unknown) }
            return .array(values.dropFirst().reduce(infer(first)) {
                merging($0, infer($1))
            })
        case .object(let members):
            var properties: [InferredProperty] = []
            for member in members {
                if let index = properties.firstIndex(where: { $0.name == member.key }) {
                    properties[index].type = merging(properties[index].type, infer(member.value))
                } else {
                    properties.append(InferredProperty(
                        name: member.key,
                        type: infer(member.value),
                        isOptional: false
                    ))
                }
            }
            return .object(InferredObject(properties: properties))
        }
    }

    private static func merging(_ lhs: InferredType, _ rhs: InferredType) -> InferredType {
        if lhs == rhs { return lhs }
        if lhs == .unknown { return rhs }
        if rhs == .unknown { return lhs }
        switch (lhs, rhs) {
        case (.object(let left), .object(let right)):
            return .object(merge(left, right))
        case (.array(let left), .array(let right)):
            return .array(merging(left, right))
        default:
            return makeUnion([lhs, rhs])
        }
    }

    private static func makeUnion(_ types: [InferredType]) -> InferredType {
        var flattened: [InferredType] = []
        for type in types {
            if case .union(let nested) = type {
                flattened.append(contentsOf: nested)
            } else if type != .unknown {
                flattened.append(type)
            }
        }
        var merged: [InferredType] = []
        for type in flattened {
            if let index = merged.firstIndex(where: {
                switch ($0, type) {
                case (.object, .object), (.array, .array): return true
                default: return false
                }
            }) {
                merged[index] = merging(merged[index], type)
            } else if !merged.contains(type) {
                merged.append(type)
            }
        }
        if merged.isEmpty { return .unknown }
        return merged.count == 1 ? merged[0] : .union(merged)
    }

    private static func merge(_ lhs: InferredObject, _ rhs: InferredObject) -> InferredObject {
        var properties = lhs.properties
        for right in rhs.properties {
            if let index = properties.firstIndex(where: { $0.name == right.name }) {
                properties[index].type = merging(properties[index].type, right.type)
                properties[index].isOptional = properties[index].isOptional || right.isOptional
            } else {
                properties.append(InferredProperty(
                    name: right.name,
                    type: right.type,
                    isOptional: true
                ))
            }
        }
        for index in properties.indices where !rhs.properties.contains(where: {
            $0.name == properties[index].name
        }) {
            properties[index].isOptional = true
        }
        return InferredObject(properties: properties)
    }
}

struct TypeScriptGenerator {
    func generate(
        input: String,
        options: TypeScriptGenerationOptions = TypeScriptGenerationOptions()
    ) throws -> String {
        let root = try JSONParser.parse(input)
        guard Self.isValidRootName(options.rootName) else {
            throw TypeScriptGenerationError.invalidRootName
        }
        return TypeScriptEmitter(rootName: options.rootName, includesExport: options.includesExport)
            .emit(root: .infer(root))
    }

    private static func isValidRootName(_ name: String) -> Bool {
        guard let first = name.first, first == "_" || first == "$" || first.isLetter,
            name.allSatisfy({ $0 == "_" || $0 == "$" || $0.isLetter || $0.isNumber })
        else {
            return false
        }
        return !reservedNames.contains(name)
    }

    private static let reservedNames: Set<String> = [
        "abstract", "any", "as", "asserts", "async", "await", "bigint", "boolean",
        "break", "case", "catch", "class", "const", "constructor", "continue",
        "debugger", "declare", "default", "delete", "do", "else", "enum", "export",
        "extends", "false", "finally", "for", "from", "function", "get", "if",
        "implements", "import", "in", "infer", "instanceof", "interface", "intrinsic",
        "is", "keyof", "let", "module", "namespace", "never", "new", "null",
        "number", "object", "of", "out", "override", "package", "private",
        "protected", "public", "readonly", "return", "satisfies", "set", "static",
        "string", "super", "switch", "symbol", "this", "throw", "true", "try",
        "type", "typeof", "undefined", "unique", "unknown", "var", "void", "while",
        "with", "yield"
    ]
}

private struct TypeScriptInterface {
    let name: String
    let object: InferredObject
}

private final class TypeScriptEmitter {
    private let rootName: String
    private let includesExport: Bool
    private var usedNames: Set<String>
    private var interfaces: [TypeScriptInterface] = []

    init(rootName: String, includesExport: Bool) {
        self.rootName = rootName
        self.includesExport = includesExport
        usedNames = []
    }

    func emit(root: InferredType) -> String {
        var rootAlias: String?
        if case .object = root {
            _ = reference(root, suggestion: rootName)
        } else {
            usedNames.insert(rootName)
            let type = reference(root, suggestion: rootName)
            rootAlias = "\(exportPrefix)type \(rootName) = \(type);"
        }

        var definitions: [String] = []
        var index = 0
        while index < interfaces.count {
            let interface = interfaces[index]
            let body = interface.object.properties.map { property in
                let name = interface.name + pascalName(property.name)
                let type = reference(property.type, suggestion: name)
                return "  \(propertyName(property.name))\(property.isOptional ? "?" : ""): \(type);"
            }.joined(separator: "\n")
            if interface.object.properties.isEmpty {
                definitions.append("\(exportPrefix)interface \(interface.name) {}")
            } else {
                definitions.append("\(exportPrefix)interface \(interface.name) {\n\(body)\n}")
            }
            index += 1
        }
        if let rootAlias {
            definitions.insert(rootAlias, at: 0)
        }
        return definitions.joined(separator: "\n\n")
    }

    private var exportPrefix: String { includesExport ? "export " : "" }

    private func reference(_ type: InferredType, suggestion: String) -> String {
        switch type {
        case .string: return "string"
        case .number: return "number"
        case .boolean: return "boolean"
        case .null: return "null"
        case .unknown: return "unknown"
        case .object(let object):
            let name = uniqueName(suggestion)
            interfaces.append(TypeScriptInterface(name: name, object: object))
            return name
        case .array(let element):
            let rendered = reference(element, suggestion: suggestion + "Item")
            return rendered.contains("|") ? "(\(rendered))[]" : "\(rendered)[]"
        case .union(let types):
            return types.map { reference($0, suggestion: suggestion) }.joined(separator: " | ")
        }
    }

    private func uniqueName(_ suggestion: String) -> String {
        let base = suggestion.isEmpty ? "Value" : suggestion
        var candidate = base
        var suffix = 2
        while usedNames.contains(candidate) {
            candidate = base + String(suffix)
            suffix += 1
        }
        usedNames.insert(candidate)
        return candidate
    }

    private func pascalName(_ name: String) -> String {
        var output = ""
        var capitalize = true
        for character in name {
            guard character.isLetter || character.isNumber else {
                capitalize = true
                continue
            }
            if output.isEmpty, character.isNumber {
                output += "Value"
            }
            output += capitalize ? character.uppercased() : String(character)
            capitalize = false
        }
        return output.isEmpty ? "Value" : output
    }

    private func propertyName(_ name: String) -> String {
        if let first = name.first, first == "_" || first == "$" || first.isLetter,
            name.allSatisfy({ $0 == "_" || $0 == "$" || $0.isLetter || $0.isNumber })
        {
            return name
        }
        return JSONRenderer.escapedString(name)
    }
}
