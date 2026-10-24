import XCTest
@testable import ClipGum

final class JSONDeveloperToolTests: XCTestCase {
    private let service = JSONToolingService()

    func testPrettyAndMinifyPreserveOrderAndNumberLexemes() throws {
        let input = #"{"z":1e+09,"a":900719925474099312345,"nested":[true,null,"x"]}"#
        let pretty = try service.format(input, indentation: .twoSpaces)
        XCTAssertTrue(pretty.hasPrefix("{\n  \"z\": 1e+09,\n  \"a\": 900719925474099312345,"))
        XCTAssertEqual(
            try service.minify(pretty),
            input
        )
    }

    func testFourSpaceAndTabIndentation() throws {
        let input = #"{"a":{"b":1}}"#
        XCTAssertEqual(
            try service.format(input, indentation: .fourSpaces),
            "{\n    \"a\": {\n        \"b\": 1\n    }\n}"
        )
        XCTAssertEqual(
            try service.format(input, indentation: .tabs),
            "{\n\t\"a\": {\n\t\t\"b\": 1\n\t}\n}"
        )
    }

    func testUnicodeSurrogatePairAndEscapesRoundTrip() throws {
        let value = try service.parse(#"{"emoji":"\uD83D\uDE00","nul":"\u0000"}"#)
        guard case .object(let members) = value,
            case .string(let emoji) = members[0].value,
            case .string(let nul) = members[1].value
        else {
            return XCTFail("Expected object strings")
        }
        XCTAssertEqual(emoji, "😀")
        XCTAssertEqual(nul.unicodeScalars.count, 1)
        XCTAssertEqual(nul.unicodeScalars.first?.value, 0)
        XCTAssertTrue(try service.minify(#"{"emoji":"\uD83D\uDE00"}"#).contains("😀"))
        XCTAssertTrue(try service.minify(#"{"nul":"\u0000"}"#).contains("\\u0000"))
    }

    func testMalformedJSONReportsExactLineAndColumn() {
        let result = service.validate("{\n  \"a\": 1,\n  \"b\": ?\n}")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.error?.line, 3)
        XCTAssertEqual(result.error?.column, 8)
        XCTAssertEqual(result.value, nil)
    }

    func testInvalidEscapeReportsOffendingCharacter() {
        let result = service.validate(#""\x""#)
        XCTAssertEqual(result.error?.line, 1)
        XCTAssertEqual(result.error?.column, 3)
    }

    func testMalformedFixturesFailSafely() {
        let fixtures = [
            "", "{", "[1,]", #"{"a":1,}"#, "01", "1.", "1e+",
            "true false", #""\uD800""#, #""\uDC00""#, "\"line\nfeed\""
        ]
        for fixture in fixtures {
            XCTAssertFalse(service.validate(fixture).isValid, "Accepted malformed fixture: \(fixture)")
        }
    }

    func testDepthBoundaryAccepts256AndRejects257() throws {
        let deepestValid = String(repeating: "[", count: 256) + "0"
            + String(repeating: "]", count: 256)
        XCTAssertNoThrow(try service.parse(deepestValid))
        let tooDeep = String(repeating: "[", count: 257) + "0"
            + String(repeating: "]", count: 257)
        XCTAssertThrowsError(try service.parse(tooDeep)) { error in
            XCTAssertTrue((error as? JSONSyntaxError)?.message.contains("256") == true)
        }
    }

    func testInputBoundaryRejectsBeforeParsing() {
        let input = "\"" + String(repeating: "a", count: JSONParser.maximumInputUTF8Bytes) + "\""
        XCTAssertThrowsError(try service.parse(input)) { error in
            XCTAssertTrue((error as? JSONSyntaxError)?.message.contains("2 MiB") == true)
        }
    }

    func testTypeScriptMergesArrayObjectsOptionalFieldsAndUnions() throws {
        let input = #"[
            {"id":1,"name":"a","nested":{"x":true}},
            {"id":2,"nested":{"x":false},"extra":null},
            {"id":"3","name":"b","nested":{"x":true}}
        ]"#
        let output = try TypeScriptGenerator().generate(input: input)
        XCTAssertEqual(output, """
        export type Root = RootItem[];

        export interface RootItem {
          id: number | string;
          name?: string;
          nested: RootItemNested;
          extra?: null;
        }

        export interface RootItemNested {
          x: boolean;
        }
        """)
        XCTAssertEqual(output, try TypeScriptGenerator().generate(input: input))
    }

    func testTypeScriptOptionsLegalNamesAndEmptyTypes() throws {
        let generator = TypeScriptGenerator()
        let output = try generator.generate(
            input: #"{"a-b":1,"class":true,"1x":[],"empty":{}}"#,
            options: TypeScriptGenerationOptions(rootName: "APIResponse", includesExport: false)
        )
        XCTAssertTrue(output.hasPrefix("interface APIResponse {"))
        XCTAssertFalse(output.contains("export "))
        XCTAssertTrue(output.contains("\"a-b\": number;"))
        XCTAssertTrue(output.contains("class: boolean;"))
        XCTAssertTrue(output.contains("\"1x\": unknown[];"))
        XCTAssertTrue(output.contains("empty: APIResponseEmpty;"))
    }

    func testTypeScriptEmptyArrayAndScalarRoots() throws {
        XCTAssertEqual(
            try TypeScriptGenerator().generate(input: "[]"),
            "export type Root = unknown[];"
        )
        XCTAssertEqual(
            try TypeScriptGenerator().generate(input: "null"),
            "export type Root = null;"
        )
        XCTAssertEqual(
            try TypeScriptGenerator().generate(input: "{}"),
            "export interface Root {}"
        )
    }

    func testTypeScriptRejectsReservedRootNameAndMalformedJSON() {
        XCTAssertThrowsError(try TypeScriptGenerator().generate(
            input: "{}",
            options: TypeScriptGenerationOptions(rootName: "interface")
        )) { error in
            XCTAssertEqual(error as? TypeScriptGenerationError, .invalidRootName)
        }
        XCTAssertThrowsError(try TypeScriptGenerator().generate(input: "{"))
    }
}
