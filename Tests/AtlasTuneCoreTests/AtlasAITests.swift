import XCTest
@testable import AtlasTuneCore

final class AtlasAITests: XCTestCase {
    // Fixture table: xAxis rpm [1000,2000,3000,4000], yAxis load [20,40,60], 3x4.
    private func table() -> CalibrationTable {
        try! TableAccessor().read(Fixtures.table3D, from: Fixtures.loadedImage())
    }

    private func session(_ samples: [LogSample], channels: [LogChannel] = LogChannel.s58Standard) -> LogSession {
        LogSession(name: "t", channels: channels, samples: samples)
    }

    private func sample(_ t: Double, rpm: Double, load: Double, extra: [String: Double] = [:]) -> LogSample {
        var values = ["rpm": rpm, "load": load]
        values.merge(extra) { _, new in new }
        return LogSample(time: t, values: values)
    }

    // MARK: Knock

    func testKnockClustersToCellAndScales() {
        // Five knock samples at rpm 4000 / load 60 → cell (row 2, col 3), peak 5°.
        var samples: [LogSample] = []
        for i in 0..<5 {
            samples.append(sample(Double(i), rpm: 4000, load: 60, extra: ["knock": Double(i + 1)]))
        }
        let report = AtlasAI().analyze(session(samples), table: table())
        let knock = report.findings(.knock)
        XCTAssertEqual(knock.count, 1)
        let f = try! XCTUnwrap(knock.first)
        XCTAssertEqual(f.cell, CellAddress(row: 2, column: 3))
        XCTAssertEqual(f.sampleCount, 5)
        XCTAssertEqual(f.peak, 5.0, accuracy: 1e-9)      // |knock| peak
        XCTAssertEqual(f.severity, .critical)             // 5° ≥ 3×1° threshold
    }

    func testKnockSignIsMagnitude() {
        // Negative retard values (timing pulled) count by magnitude.
        let samples = (0..<4).map { sample(Double($0), rpm: 1000, load: 20, extra: ["knock": -2.0]) }
        let report = AtlasAI().analyze(session(samples), table: table())
        let f = try! XCTUnwrap(report.findings(.knock).first)
        XCTAssertEqual(f.cell, CellAddress(row: 0, column: 0))
        XCTAssertEqual(f.peak, 2.0, accuracy: 1e-9)
        XCTAssertEqual(f.severity, .warning)              // 2° ≥ 1.5× but < 3×
    }

    func testKnockBelowThresholdIgnored() {
        let samples = (0..<10).map { sample(Double($0), rpm: 3000, load: 40, extra: ["knock": 0.4]) }
        let report = AtlasAI().analyze(session(samples), table: table())
        XCTAssertTrue(report.findings(.knock).isEmpty)
    }

    func testSingleKnockEventSurfacesByDefault() {
        // A real pull sweeps cells, so one dangerous event per cell must still flag (default min 1).
        let samples = [sample(0, rpm: 4000, load: 60, extra: ["knock": 6.0])]
        let f = try! XCTUnwrap(AtlasAI().analyze(session(samples), table: table()).findings(.knock).first)
        XCTAssertEqual(f.severity, .critical)
        XCTAssertEqual(f.sampleCount, 1)
    }

    func testMinSamplesPerCellFilterIsConfigurable() {
        // Raising the gate suppresses cells with too few offending samples.
        let ai = AtlasAI(thresholds: .init(minSamplesPerCell: 3))
        let two = (0..<2).map { sample(Double($0), rpm: 4000, load: 60, extra: ["knock": 6.0]) }
        XCTAssertTrue(ai.analyze(session(two), table: table()).isClean)
        let three = (0..<3).map { sample(Double($0), rpm: 4000, load: 60, extra: ["knock": 6.0]) }
        XCTAssertFalse(ai.analyze(session(three), table: table()).isClean)
    }

    // MARK: Lean

    func testLeanUnderLoadFlagged() {
        // Lambda 0.98 at load 60 (≥ leanMinLoad default 70? no — 60 < 70, so NOT flagged).
        let notLoaded = (0..<5).map { sample(Double($0), rpm: 3000, load: 60, extra: ["lambda": 0.98]) }
        XCTAssertTrue(AtlasAI().analyze(session(notLoaded), table: table()).findings(.lean).isEmpty)

        // Same lambda at load 90 → lean finding.
        let loaded = (0..<5).map { sample(Double($0), rpm: 3000, load: 90, extra: ["lambda": 0.98]) }
        let report = AtlasAI().analyze(session(loaded), table: table())
        let f = try! XCTUnwrap(report.findings(.lean).first)
        XCTAssertEqual(f.peak, 0.98, accuracy: 1e-9)
        XCTAssertEqual(f.severity, .warning)              // 0.98 - 0.90 = 0.08 → warning
    }

    func testRichMixtureNotFlagged() {
        let samples = (0..<5).map { sample(Double($0), rpm: 3000, load: 95, extra: ["lambda": 0.80]) }
        XCTAssertTrue(AtlasAI().analyze(session(samples), table: table()).findings(.lean).isEmpty)
    }

    func testVeryLeanIsCritical() {
        let samples = (0..<5).map { sample(Double($0), rpm: 4000, load: 100, extra: ["lambda": 1.05]) }
        let f = try! XCTUnwrap(AtlasAI().analyze(session(samples), table: table()).findings(.lean).first)
        XCTAssertEqual(f.severity, .critical)             // 1.05 - 0.90 = 0.15 ≥ 0.10
    }

    // MARK: Boost deviation

    private var withTarget: [LogChannel] {
        LogChannel.s58Standard + [LogChannel(id: "boost_target", name: "Boost Target", unit: "psi")]
    }

    func testOverboostFlaggedWithSense() {
        let samples = (0..<4).map {
            sample(Double($0), rpm: 4000, load: 90, extra: ["boost": 21.0, "boost_target": 18.0])
        }
        let report = AtlasAI().analyze(session(samples, channels: withTarget), table: table())
        let f = try! XCTUnwrap(report.findings(.boostDeviation).first)
        XCTAssertEqual(f.peak, 3.0, accuracy: 1e-9)
        XCTAssertTrue(f.message.contains("over target"))
        XCTAssertEqual(f.severity, .warning)              // 3 psi ≥ 1.5×2
    }

    func testUnderboostFlaggedWithSense() {
        let samples = (0..<4).map {
            sample(Double($0), rpm: 3000, load: 80, extra: ["boost": 10.0, "boost_target": 17.0])
        }
        let report = AtlasAI().analyze(session(samples, channels: withTarget), table: table())
        let f = try! XCTUnwrap(report.findings(.boostDeviation).first)
        XCTAssertEqual(f.peak, 7.0, accuracy: 1e-9)
        XCTAssertTrue(f.message.contains("under target"))
        XCTAssertEqual(f.severity, .critical)             // 7 psi ≥ 3×2
    }

    func testNoBoostTargetChannelMeansNoBoostFindings() {
        // Without a target channel there is nothing to compare against.
        let samples = (0..<5).map { sample(Double($0), rpm: 4000, load: 90, extra: ["boost": 25.0]) }
        let report = AtlasAI().analyze(session(samples), table: table())
        XCTAssertTrue(report.findings(.boostDeviation).isEmpty)
    }

    func testWithinToleranceNotFlagged() {
        let samples = (0..<5).map {
            sample(Double($0), rpm: 4000, load: 90, extra: ["boost": 18.5, "boost_target": 18.0])
        }
        let report = AtlasAI().analyze(session(samples, channels: withTarget), table: table())
        XCTAssertTrue(report.findings(.boostDeviation).isEmpty)   // 0.5 psi < 2.0
    }

    func testBoostTargetChannelDetection() {
        XCTAssertEqual(AtlasAI.boostTargetChannelID(in: session([], channels: withTarget)), "boost_target")
        XCTAssertNil(AtlasAI.boostTargetChannelID(in: session([])))          // only actual boost
    }

    // MARK: Report shape

    func testReportSortingAndSummary() {
        var samples: [LogSample] = []
        // Critical knock at (0,0)
        samples += (0..<4).map { sample(Double($0), rpm: 1000, load: 20, extra: ["knock": 6.0]) }
        // Warning lean at (2,3)
        samples += (0..<4).map { sample(Double(10 + $0), rpm: 4000, load: 90, extra: ["lambda": 0.96]) }
        let report = AtlasAI().analyze(session(samples), table: table())

        XCTAssertEqual(report.findings.count, 2)
        XCTAssertEqual(report.findings.first?.severity, .critical)   // most-severe first
        XCTAssertEqual(report.mostSevere, .critical)
        XCTAssertEqual(report.count(.critical), 1)
        XCTAssertEqual(report.count(.warning), 1)
        XCTAssertFalse(report.isClean)
        XCTAssertEqual(report.totalSamples, 8)
        XCTAssertEqual(report.analyzedSamples, 8)
    }

    func testBoundingRegion() {
        var samples: [LogSample] = []
        samples += (0..<3).map { sample(Double($0), rpm: 1000, load: 20, extra: ["knock": 3.0]) }   // (0,0)
        samples += (0..<3).map { sample(Double(10 + $0), rpm: 3000, load: 60, extra: ["knock": 3.0]) } // (2,2)
        let report = AtlasAI().analyze(session(samples), table: table())
        let region = try! XCTUnwrap(report.boundingRegion(for: .knock))
        XCTAssertEqual(region.rows, 0..<3)
        XCTAssertEqual(region.columns, 0..<3)
        XCTAssertNil(report.boundingRegion(for: .lean))
    }

    func testCleanSessionProducesNoFindings() {
        let samples = (0..<20).map {
            sample(Double($0), rpm: 2500, load: 50, extra: ["knock": 0, "lambda": 0.82])
        }
        let report = AtlasAI().analyze(session(samples), table: table())
        XCTAssertTrue(report.isClean)
        XCTAssertEqual(report.analyzedSamples, 20)
    }

    func testSamplesMissingXAreNotAnalyzed() {
        let samples = [
            LogSample(time: 0, values: ["load": 50, "knock": 6]),   // no rpm → skipped
            sample(1, rpm: 4000, load: 60, extra: ["knock": 6]),
            sample(2, rpm: 4000, load: 60, extra: ["knock": 6]),
            sample(3, rpm: 4000, load: 60, extra: ["knock": 6]),
        ]
        let report = AtlasAI().analyze(session(samples), table: table())
        XCTAssertEqual(report.totalSamples, 4)
        XCTAssertEqual(report.analyzedSamples, 3)
        XCTAssertEqual(report.findings(.knock).first?.sampleCount, 3)
    }

    // MARK: End-to-end from an imported CSV

    func testEndToEndFromImportedLog() throws {
        let csv = """
        Time (s),RPM (rpm),Calc load (%),Knock (deg),AFR (afr),Boost Pressure (psi),Boost Target (psi)
        0.0,4000,90,4.0,12.0,22,18
        0.1,4000,90,4.5,12.1,22,18
        0.2,4000,90,5.0,12.0,23,18
        0.3,4000,90,3.5,12.2,22,18
        """
        let session = try CSVLogImporter().session(from: csv, name: "track pull")
        let report = AtlasAI().analyze(session, table: table())
        // Knock cluster + overboost cluster both at the same cell; AFR→lambda ≈ 0.82 (rich, not lean).
        XCTAssertFalse(report.findings(.knock).isEmpty)
        XCTAssertFalse(report.findings(.boostDeviation).isEmpty)
        XCTAssertTrue(report.findings(.lean).isEmpty)
        XCTAssertEqual(report.mostSevere, .critical)      // 5° knock
    }
}
