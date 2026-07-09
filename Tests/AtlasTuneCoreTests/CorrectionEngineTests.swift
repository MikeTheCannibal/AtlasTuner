import XCTest
@testable import AtlasTuneCore

final class CorrectionEngineTests: XCTestCase {
    private let engine = CorrectionEngine()

    // MARK: Table fixtures of each category

    private func makeTable(category: CalibrationCategory, unit: String, name: String = "Map",
                           fill: Double = 10.0, range: ClosedRange<Double>? = 0...30) -> CalibrationTable {
        let def = TableDefinition(
            id: "t.\(category.rawValue)", name: name, category: category, subcategory: "s",
            address: 0, dataType: .float32, scaling: .identity, unit: unit,
            rows: 3, columns: 4,
            xAxis: .fixed(id: "x", name: "RPM", unit: "rpm", values: [1000, 2000, 3000, 4000]),
            yAxis: .fixed(id: "y", name: "Load", unit: "%", values: [20, 40, 60]),
            valueRange: range
        )
        let values = Array(repeating: Array(repeating: fill, count: 4), count: 3)
        return CalibrationTable(definition: def, xAxis: [1000, 2000, 3000, 4000], yAxis: [20, 40, 60], values: values)
    }

    private func finding(_ category: AtlasCategory, cell: CellAddress = CellAddress(row: 2, column: 3),
                         peak: Double, severity: AtlasSeverity = .warning) -> AtlasFinding {
        AtlasFinding(category: category, severity: severity, cell: cell, sampleCount: 3,
                     peak: peak, mean: peak, message: "m", suggestion: "s")
    }

    // MARK: Knock → ignition

    func testKnockOnIgnitionPullsTimingWithGainAndCap() {
        let ignition = makeTable(category: .ignition, unit: "°")
        // 1.2° retard × 0.5 gain = 0.6° — under the 1.0° cap, not step-limited.
        let c = try! XCTUnwrap(engine.correction(for: finding(.knock, peak: 1.2), table: ignition))
        XCTAssertEqual(c.operation, .subtract(0.6))
        XCTAssertFalse(c.stepLimited)
        XCTAssertTrue(c.summary.contains("Pull 0.6°"))

        // 5° retard × 0.5 = 2.5° wanted → capped at 1.0°/pass and flagged step-limited.
        let capped = try! XCTUnwrap(engine.correction(for: finding(.knock, peak: 5.0), table: ignition))
        XCTAssertEqual(capped.operation, .subtract(1.0))
        XCTAssertTrue(capped.stepLimited)
    }

    func testKnockNotSuggestedOnWrongTable() {
        XCTAssertNil(engine.correction(for: finding(.knock, peak: 5), table: makeTable(category: .fuel, unit: "λ")))
        XCTAssertNil(engine.correction(for: finding(.knock, peak: 5), table: makeTable(category: .boost, unit: "psi")))
    }

    // MARK: Mixture → fuel

    func testLeanOnLambdaTargetTableLowersTarget() {
        // Lambda-target table: richer = LOWER value, so a lean finding subtracts (negative %).
        let fuel = makeTable(category: .fuel, unit: "λ", fill: 0.85, range: 0.6...1.1)
        // peak 0.98 vs band mid (0.90+0.72)/2 = 0.81 → full +21%, damped 10.5% → capped 3%.
        let c = try! XCTUnwrap(engine.correction(for: finding(.lean, peak: 0.98), table: fuel))
        XCTAssertEqual(c.operation, .percentChange(-3.0))
        XCTAssertTrue(c.stepLimited)
        XCTAssertTrue(c.summary.contains("Richen"))
    }

    func testLeanOnQuantityFuelTableAddsFuel() {
        // Quantity-style fuel table (e.g. injection ms): richer = HIGHER value.
        let fuel = makeTable(category: .fuel, unit: "ms", name: "Injection Base")
        let c = try! XCTUnwrap(engine.correction(for: finding(.lean, peak: 0.98), table: fuel))
        XCTAssertEqual(c.operation, .percentChange(3.0))
        XCTAssertTrue(c.summary.contains("Richen"))
    }

    func testRichOnLambdaTargetTableRaisesTarget() {
        let fuel = makeTable(category: .fuel, unit: "λ", fill: 0.85, range: 0.6...1.1)
        // peak 0.65 vs band mid 0.81 → full −19.8%, damped −9.9% → capped 3%, leaning.
        let c = try! XCTUnwrap(engine.correction(for: finding(.rich, peak: 0.65), table: fuel))
        XCTAssertEqual(c.operation, .percentChange(3.0))
        XCTAssertTrue(c.summary.contains("Lean"))
    }

    func testMixtureNotSuggestedOffFuelTables() {
        XCTAssertNil(engine.correction(for: finding(.lean, peak: 0.98), table: makeTable(category: .ignition, unit: "°")))
    }

    func testTinyMixtureErrorProducesNoSuggestion() {
        // Peak equal to band mid → 0% correction → no suggestion noise.
        let fuel = makeTable(category: .fuel, unit: "λ")
        XCTAssertNil(engine.correction(for: finding(.lean, peak: 0.81), table: fuel))
    }

    // MARK: Boost deviation → boost

    func testOverboostLowersTargetAndUnderboostRaisesIt() {
        let boost = makeTable(category: .boost, unit: "psi")
        // +4.8 psi over × 0.5 = 2.4 wanted → capped 1.0, lower.
        let over = try! XCTUnwrap(engine.correction(for: finding(.boostDeviation, peak: 4.8), table: boost))
        XCTAssertEqual(over.operation, .subtract(1.0))
        XCTAssertTrue(over.stepLimited)
        XCTAssertTrue(over.summary.contains("Lower"))
        // −1.4 psi under × 0.5 = 0.7 → raise, uncapped.
        let under = try! XCTUnwrap(engine.correction(for: finding(.boostDeviation, peak: -1.4), table: boost))
        XCTAssertEqual(under.operation, .add(0.7))
        XCTAssertFalse(under.stepLimited)
        XCTAssertTrue(under.summary.contains("Raise"))
    }

    // MARK: Report-level plumbing

    func testCorrectionsFilterToOpenTableAndKeepSeverityOrder() {
        let report = AnalysisReport(findings: [
            finding(.knock, cell: CellAddress(row: 0, column: 0), peak: 4, severity: .critical),
            finding(.lean, cell: CellAddress(row: 1, column: 1), peak: 0.95, severity: .warning),
            finding(.boostDeviation, cell: CellAddress(row: 2, column: 2), peak: 3, severity: .warning),
        ], totalSamples: 10, analyzedSamples: 10)

        let onIgnition = engine.corrections(for: report, table: makeTable(category: .ignition, unit: "°"))
        XCTAssertEqual(onIgnition.map(\.category), [.knock])

        let onFuel = engine.corrections(for: report, table: makeTable(category: .fuel, unit: "λ"))
        XCTAssertEqual(onFuel.map(\.category), [.lean])

        let onBoost = engine.corrections(for: report, table: makeTable(category: .boost, unit: "psi"))
        XCTAssertEqual(onBoost.map(\.category), [.boostDeviation])
    }

    // MARK: The safety property end-to-end

    func testAppliedCorrectionStaysInsideSafeRangeViaEditEngine() {
        // Ignition table already at its lower safe bound: pulling more timing must clamp, not
        // punch through — the whole apply path (EditEngine → setValue) enforces valueRange.
        let ignition = makeTable(category: .ignition, unit: "°", fill: 0.4, range: 0...45)
        let c = try! XCTUnwrap(engine.correction(for: finding(.knock, peak: 6.0), table: ignition))
        let edited = EditEngine().apply(c.operation, to: ignition, region: c.region)
        XCTAssertEqual(edited.value(row: 2, column: 3), 0.0)          // clamped at range floor
        XCTAssertEqual(edited.value(row: 0, column: 0), 0.4)          // untouched cells intact
    }

    func testApplyThenReanalyzeConverges() throws {
        // The intended loop: overboost → suggestion → apply → next log shows less error →
        // smaller suggestion. Two passes of the loop shrink the correction monotonically.
        let boost = makeTable(category: .boost, unit: "psi", fill: 18.0)
        let first = try XCTUnwrap(engine.correction(for: finding(.boostDeviation, peak: 4.8), table: boost))
        let afterFirst = EditEngine().apply(first.operation, to: boost, region: first.region)
        XCTAssertEqual(afterFirst.value(row: 2, column: 3), 17.0)     // 18 − 1.0 cap

        // Next session: error reduced by the applied step (idealised car).
        let second = try XCTUnwrap(engine.correction(for: finding(.boostDeviation, peak: 4.8 - 1.0), table: afterFirst))
        let secondStep: Double
        if case let .subtract(v) = second.operation { secondStep = v } else { secondStep = .nan }
        XCTAssertEqual(secondStep, 1.0)                               // still capped — keep iterating
        let third = try XCTUnwrap(engine.correction(for: finding(.boostDeviation, peak: 1.2), table: afterFirst))
        if case let .subtract(v) = third.operation {
            XCTAssertEqual(v, 0.6, accuracy: 1e-9)                    // gain-damped, below cap now
        } else {
            XCTFail("expected subtract")
        }
        XCTAssertFalse(third.stepLimited)
    }

    // MARK: End-to-end: CSV → analyze → correct

    func testFullPipelineFromCSVToSuggestions() throws {
        let csv = """
        Time (s),RPM (rpm),Calc load (%),Knock (deg),Boost Pressure (psi),Boost Target (psi)
        0.0,4000,60,-4.0,22,18
        0.1,4000,60,-4.5,22,18
        0.2,4000,60,-5.0,23,18
        """
        let session = try CSVLogImporter().session(from: csv, name: "pull")
        let ignition = makeTable(category: .ignition, unit: "°")
        let report = AtlasAI().analyze(session, table: ignition)
        let corrections = CorrectionEngine().corrections(for: report, table: ignition)
        XCTAssertEqual(corrections.count, 1)                           // knock only — boost needs a boost map
        let c = corrections[0]
        XCTAssertEqual(c.category, .knock)
        XCTAssertEqual(c.operation, .subtract(1.0))                    // 5°×0.5 capped at 1.0
        XCTAssertTrue(c.stepLimited)
        XCTAssertEqual(c.region, CellRegion(row: 2, column: 3))
    }
}
