import XCTest
@testable import AtlasTuneCore

final class CSVLogImporterTests: XCTestCase {
    private let importer = CSVLogImporter()

    // MARK: Real-world header shapes

    func testMHDStyleLog() throws {
        // MHD exports "Name (unit)" headers and a leading time column.
        let csv = """
        Time (s),RPM (rpm),Boost Pressure (psi),Calc load (%),Ignition timing avg (deg),Knock (deg)
        0.00,1500,5.2,45,12.0,0.0
        0.05,3200,14.8,88,8.5,-1.5
        0.10,5800,21.3,99,6.0,-3.0
        """
        let session = try importer.session(from: csv, name: "MHD Log")
        let ids = session.channels.map(\.id)
        XCTAssertEqual(ids, ["rpm", "boost", "load", "ign", "knock"])
        XCTAssertEqual(session.sampleCount, 3)
        XCTAssertEqual(session.samples[1].value(.rpm), 3200)
        XCTAssertEqual(session.samples[2].value(.boost), 21.3)
        XCTAssertEqual(session.samples[1].time, 0.05, accuracy: 1e-9)
        XCTAssertEqual(session.duration, 0.10, accuracy: 1e-9)
    }

    func testBootmod3StyleLog() throws {
        // BM3 exports lowercase snake-ish headers, no unit suffixes.
        let csv = """
        time,rpm,boost,timing,afr,wastegate
        0,1000,2.0,15,12.5,20
        1,4000,18.0,7,11.8,65
        """
        let session = try importer.session(from: csv, name: "BM3 Log")
        let ids = session.channels.map(\.id)
        // afr recognised and converted to lambda (no explicit lambda column present).
        XCTAssertEqual(ids, ["rpm", "boost", "ign", "lambda", "wgdc"])
        // 11.8 AFR / 14.7 stoich ≈ 0.8027 lambda
        XCTAssertEqual(try XCTUnwrap(session.samples[1].value(.lambda)), 11.8 / 14.7, accuracy: 1e-6)
    }

    func testAFRKeptWhenLambdaPresent() throws {
        let csv = """
        time,rpm,load,lambda,afr
        0,2000,50,0.90,13.2
        """
        let session = try importer.session(from: csv, name: "Both")
        let ids = session.channels.map(\.id)
        XCTAssertTrue(ids.contains("lambda"))
        XCTAssertEqual(session.samples[0].value(.lambda), 0.90)     // real lambda column wins
        XCTAssertTrue(ids.contains("afr"))                          // AFR preserved separately
        XCTAssertEqual(session.samples[0].value(channelID: "afr"), 13.2)
    }

    func testAFRConversionCanBeDisabled() throws {
        let plain = CSVLogImporter(options: .init(afrToLambdaStoich: nil))
        let session = try plain.session(from: "time,afr\n0,14.7\n", name: "x")
        XCTAssertEqual(session.channels.map(\.id), ["afr"])
        XCTAssertEqual(session.samples[0].value(channelID: "afr"), 14.7)
    }

    // MARK: Channel recognition breadth

    func testChannelAliasesResolve() {
        let cases: [(String, LogChannel)] = [
            ("Engine Speed", .rpm), ("rpm", .rpm),
            ("Calculated Load", .load), ("Boost Pressure", .boost),
            ("Ignition Timing", .ignitionTiming), ("Timing", .ignitionTiming),
            ("Knock Retard", .knock), ("Wastegate Duty", .wgdc),
            ("Intake Air Temp", .iat), ("Coolant Temp", .coolant),
        ]
        for (header, expected) in cases {
            XCTAssertEqual(CSVLogImporter.canonicalChannel(name: header)?.id, expected.id, header)
        }
    }

    func testUnknownAndNearMissColumnsPreserved() throws {
        // "Boost Target" must NOT collapse into "Boost"; it is preserved as its own channel.
        let csv = """
        time,Boost Pressure (psi),Boost Target (psi),Fuel Pressure (bar)
        0,15,18,120
        """
        let session = try importer.session(from: csv, name: "x")
        let ids = session.channels.map(\.id)
        XCTAssertEqual(ids, ["boost", "boost_target", "fuel_pressure"])
        XCTAssertEqual(session.channels[2].unit, "bar")
        XCTAssertEqual(session.samples[0].value(channelID: "boost_target"), 18)
    }

    func testDuplicateCanonicalColumnsDoNotCollide() throws {
        let csv = "time,rpm,RPM\n0,1000,1001\n"
        let session = try importer.session(from: csv, name: "x")
        let ids = session.channels.map(\.id)
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(ids[0], "rpm")
        XCTAssertNotEqual(ids[1], "rpm")            // second one preserved under a distinct id
        XCTAssertEqual(session.samples[0].value(.rpm), 1000)
    }

    // MARK: Parsing robustness

    func testCRLFAndBOMAndTrailingNewline() throws {
        let csv = "\u{FEFF}time,rpm\r\n0,1000\r\n1,2000\r\n"
        let session = try importer.session(from: csv, name: "x")
        XCTAssertEqual(session.sampleCount, 2)
        XCTAssertEqual(session.samples[1].value(.rpm), 2000)
    }

    func testQuotedFieldsTokenize() {
        // Commas inside quotes stay in the field; "" is an escaped quote.
        let csv = "a,\"b,c\",\"he said \"\"hi\"\"\"\n1,\"2,3\",x\n"
        let rows = CSVLogImporter.parseCSV(csv)
        XCTAssertEqual(rows[0], ["a", "b,c", "he said \"hi\""])
        XCTAssertEqual(rows[1], ["1", "2,3", "x"])
    }

    func testQuotedHeaderUnitParses() throws {
        let csv = "time,\"Torque (Nm)\",rpm\n0,\"1,234\",1500\n"
        let session = try importer.session(from: csv, name: "x")
        XCTAssertEqual(session.channels.map(\.id), ["torque", "rpm"])
        XCTAssertEqual(session.channels[0].unit, "Nm")           // unit parsed out of quoted header
        XCTAssertNil(session.samples[0].value(.torque))          // "1,234" not numeric → omitted
        XCTAssertEqual(session.samples[0].value(.rpm), 1500)
    }

    func testSemicolonDelimiterAutoDetected() throws {
        let csv = "time;rpm;boost\n0;1500;5\n1;3000;12\n"
        let session = try importer.session(from: csv, name: "x")
        XCTAssertEqual(session.channels.map(\.id), ["rpm", "boost"])
        XCTAssertEqual(session.samples[1].value(.boost), 12)
    }

    func testTabDelimiterAutoDetected() throws {
        let csv = "time\trpm\tload\n0\t1500\t40\n"
        let session = try importer.session(from: csv, name: "x")
        XCTAssertEqual(session.channels.map(\.id), ["rpm", "load"])
    }

    func testMillisecondTimeConverted() throws {
        let csv = "Time (ms),rpm\n0,1000\n500,2000\n1000,3000\n"
        let session = try importer.session(from: csv, name: "x")
        XCTAssertEqual(session.samples[1].time, 0.5, accuracy: 1e-9)
        XCTAssertEqual(session.duration, 1.0, accuracy: 1e-9)
    }

    func testMissingTimeColumnSynthesisesIndex() throws {
        let csv = "rpm,load\n1000,40\n2000,50\n3000,60\n"
        let session = try importer.session(from: csv, name: "x")
        XCTAssertEqual(session.samples.map(\.time), [0, 1, 2])
        XCTAssertEqual(session.channels.map(\.id), ["rpm", "load"])
    }

    func testMissingCellsAndBlankRowsSkipped() throws {
        let csv = """
        time,rpm,boost
        0,1500,5

        1,,12
        2,3000,
        """
        let session = try importer.session(from: csv, name: "x")
        XCTAssertEqual(session.sampleCount, 3)                 // blank line dropped
        XCTAssertNil(session.samples[1].value(.rpm))          // empty cell omitted
        XCTAssertEqual(session.samples[1].value(.boost), 12)
        XCTAssertNil(session.samples[2].value(.boost))
    }

    func testRaggedRowsHandled() throws {
        let csv = "time,rpm,boost\n0,1500\n1,3000,14,99\n"   // short row, then long row
        let session = try importer.session(from: csv, name: "x")
        XCTAssertNil(session.samples[0].value(.boost))        // missing trailing field
        XCTAssertEqual(session.samples[1].value(.boost), 14)  // extra field ignored
    }

    // MARK: Errors

    func testEmptyThrows() {
        XCTAssertThrowsError(try importer.session(from: "   \n  \n", name: "x")) {
            XCTAssertEqual($0 as? CSVLogImporter.ImportError, .empty)
        }
    }

    func testHeaderOnlyThrows() {
        XCTAssertThrowsError(try importer.session(from: "time,rpm,boost\n", name: "x")) {
            XCTAssertEqual($0 as? CSVLogImporter.ImportError, .noDataRows)
        }
    }

    func testNonNumericBodyThrows() {
        // Header parses, rows exist, but no cell yields a number → no usable samples.
        XCTAssertThrowsError(try importer.session(from: "time,rpm\na,b\nc,d\n", name: "x")) {
            XCTAssertEqual($0 as? CSVLogImporter.ImportError, .noDataRows)
        }
    }

    // MARK: Integration with the active-cell tracker (the flagship payoff)

    func testImportedLogDrivesHeatMap() throws {
        let table = try TableAccessor().read(Fixtures.table3D, from: Fixtures.loadedImage())
        // xAxis rpm [1000,2000,3000,4000], yAxis load [20,40,60].
        let csv = """
        time,rpm,load
        0.0,1000,20
        0.1,1000,20
        0.2,1000,20
        0.3,4000,60
        """
        let session = try importer.session(from: csv, name: "drive")
        var tracker = ActiveCellTracker(table: table)
        tracker.record(session: session, x: .rpm, y: .load)

        XCTAssertEqual(tracker.totalHits, 4)
        XCTAssertEqual(tracker.hits[0][0], 3)                  // (load 20, rpm 1000) hit 3x
        XCTAssertEqual(tracker.hits[2][3], 1)                  // (load 60, rpm 4000) hit 1x
        let heat = tracker.heatMap()
        XCTAssertEqual(heat[0][0], 1.0, accuracy: 1e-9)
        XCTAssertEqual(heat[2][3], 1.0 / 3.0, accuracy: 1e-9)
    }
}
