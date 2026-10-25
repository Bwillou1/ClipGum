import Foundation
import XCTest
@testable import ClipGum

final class OfficeTransformTests: XCTestCase {
    private let invariants = DataInvariantValidator()
    private let validator = OutputValidator()

    func testProtectedNumbersDatesCurrencyAndFormulaCanMoveWithoutChanging() {
        let source = "Budget 12,50 € (10%) due 24/10/2026; formula =SUM(A1:A3)."
        let output = "Due 24/10/2026, formula =SUM(A1:A3). Budget 10% and 12,50 €."
        XCTAssertTrue(invariants.issues(source: source, output: output).isEmpty)
    }

    func testEveryProtectedDataKindHasAnExportBlockingIssue() {
        let source = "Budget 12,50 € (10%) due 24/10/2026; formula =SUM(A1:A3)."
        let cases: [(String, ValidationIssue.Code)] = [
            ("Budget 12.50 € (10%) due 24/10/2026; formula =SUM(A1:A3).", .numbersChanged),
            ("Budget 12,50 (10%) due 24/10/2026; formula =SUM(A1:A3).", .currencyChanged),
            ("Budget 12,50 € (11%) due 24/10/2026; formula =SUM(A1:A3).", .numbersChanged),
            ("Budget 12,50 € (10%) due 25/10/2026; formula =SUM(A1:A3).", .numbersChanged),
            ("Budget 12,50 € (10%) due 24/10/2026; formula =SUM(A1:A4).", .formulaChanged)
        ]
        for (output, code) in cases {
            let issues = invariants.issues(source: source, output: output)
            XCTAssertTrue(issues.contains { $0.code == code && $0.severity == .error }, output)
        }
    }

    func testGroupedThousandsAndDollarSignsAreProtected() {
        let source = "Totals: $1,000.50 and 1 234,50 €."
        XCTAssertTrue(invariants.issues(source: source, output: source).isEmpty)
        XCTAssertTrue(invariants.issues(
            source: source,
            output: "Totals: $1000.50 and 1 234,50 €."
        ).contains { $0.code == .numbersChanged })
        XCTAssertTrue(invariants.issues(
            source: source,
            output: "Totals: 1,000.50 and 1 234,50 €."
        ).contains { $0.code == .currencyChanged })
    }

    func testEnglishAndFrenchNamedDatesAreComparedAsCompleteTokens() {
        let source = "Meet 24 October 2026, then 25 décembre 2026; planning May 2026."
        XCTAssertTrue(invariants.issues(source: source, output: source).isEmpty)
        for output in [
            source.replacingOccurrences(of: "October", with: "November"),
            source.replacingOccurrences(of: "décembre", with: "novembre"),
            source.replacingOccurrences(of: "May 2026", with: "June 2026")
        ] {
            XCTAssertTrue(invariants.issues(source: source, output: output).contains {
                $0.code == .numbersChanged
            }, output)
        }
    }

    func testProfessionalEmailDiscrepancyIsProminentlyMachineReadableAndBlocked() {
        let source = "Please confirm the 12,50 € invoice by 24/10/2026. Formula: =SUM(A1:A3)."
        let valid = validator.validate(action: .professionalEmail, source: source, output: source)
        XCTAssertTrue(valid.canExport)
        XCTAssertFalse(valid.hasDataInvariantFailure)

        let report = validator.validate(
            action: .professionalEmail,
            source: source,
            output: source.replacingOccurrences(of: "12,50", with: "13,50")
        )
        XCTAssertFalse(report.canExport)
        XCTAssertTrue(report.hasDataInvariantFailure)
        XCTAssertTrue(report.errors.contains { $0.code == .numbersChanged })
    }

    func testCorrectionAndSlackSummaryAlsoRejectFormulaChanges() {
        for action in [SmartPasteAction.correction, .slackSummary] {
            let report = validator.validate(
                action: action,
                source: "Review =SUM(A1:A3) before 24/10/2026 with the team.",
                output: "Review =SUM(A1:A4) before 24/10/2026 with the team."
            )
            XCTAssertTrue(report.errors.contains { $0.code == .formulaChanged }, action.rawValue)
            XCTAssertTrue(report.hasDataInvariantFailure)
            XCTAssertFalse(report.canExport)
        }
    }

    func testOfficePromptsForbidInventedFactsCommitmentsAndDeadlines() {
        let correction = PromptTemplate(action: .correction).instructions
        XCTAssertTrue(correction.contains("CORRECTION ONLY"))
        XCTAssertTrue(correction.contains("FRANÇAIS / ENGLISH"))

        let email = PromptTemplate(action: .professionalEmail).instructions
        for phrase in ["PROFESSIONAL EMAIL", "Never invent", "commitment", "deadline", "formula"] {
            XCTAssertTrue(email.contains(phrase), phrase)
        }
        let slack = PromptTemplate(action: .slackSummary).instructions
        for phrase in ["ACTION-ORIENTED", "Decisions", "Open actions", "Blockers", "Do not turn a question"] {
            XCTAssertTrue(slack.contains(phrase), phrase)
        }
    }

    func testProfessionalEmailInferenceReceivesOnlyCleanedBoundedInput() async throws {
        let input = "Budget 12,50 € token=Abcd1234efgh5678"
        let cleaned = RuleCleaningService().clean(input).cleaned
        let engine = MockManagedInferenceEngine(chunks: [cleaned])
        let pipeline = SmartPastePipeline(engine: engine)
        let stream = try await pipeline.inferenceStream(
            action: .professionalEmail,
            input: input,
            maxTokens: 128
        )
        let events = try await collectPipelineEvents(stream)
        guard case .completed(let result)? = events.last else {
            return XCTFail("Missing completion")
        }
        XCTAssertTrue(result.validation.canExport)
        let calls = await engine.transformCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.input, cleaned)
        XCTAssertEqual(calls.first?.maxTokens, 128)
        XCTAssertFalse(calls.first?.input.contains("Abcd1234efgh5678") == true)
        XCTAssertTrue(calls.first?.prompt.contains("PROFESSIONAL EMAIL") == true)
    }

    func testNewDeterministicActionsBypassInference() async throws {
        let engine = MockManagedInferenceEngine()
        let pipeline = SmartPastePipeline(engine: engine)
        let repaired = try pipeline.mechanicalResult(
            action: .repairPDF,
            input: "A hard-\nwrapped word."
        )
        XCTAssertEqual(repaired?.cleaned, "A hardwrapped word.")
        let table = try pipeline.mechanicalResult(
            action: .convertTable,
            input: "Name\tAmount\nAda\t12,50",
            options: DeveloperActionOptions(
                table: TableConversionOptions(format: .csv, delimiter: .semicolon)
            )
        )
        XCTAssertEqual(table?.cleaned, "Name;Amount\r\nAda;\"12,50\"")
        XCTAssertNil(try pipeline.mechanicalResult(action: .professionalEmail, input: "text"))
        XCTAssertNil(try pipeline.mechanicalResult(action: .slackSummary, input: "text"))
        let calls = await engine.transformCalls
        XCTAssertTrue(calls.isEmpty)
    }
}
