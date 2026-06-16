import XCTest
@testable import AtlasTuneCore

final class CSVImporterTests: XCTestCase {
    func testRoundTripWithExporter() throws {
        var original = LogSession(name: "Drive", channels: [.rpm, .boost, .lambda])
        original.append(LogSample(time: 0.0, values: ["rpm": 1000, "boost": 5.5, "lambda": 0.90]))
        original.append(LogSample(time: 0.1, values: ["rpm": 2500, "boost": 12.0, "lambda": 0.85]))

        let csv = CSVExporter().csv(for: original)
        let imported = try CSVImporter().session(from: csv)

        XCTAssertEqual(imported.samples.count, 2)
        // Channel names round-trip to the canonical channels (ids preserved).
        XCTAssertEqual(imported.channels.map(\.id), ["rpm", "boost", "lambda"])
        XCTAssertEqual(imported.samples[1].value(.rpm), 2500)
        XCTAssertEqual(imported.samples[0].value(.lambda), 0.90, accuracy: 1e-9)
    }

    func testGenericHeadersMapToChannelsByAlias() throws {
        let csv = """
        Time,RPM,Engine Load (%),Boost (psi)
        0,800,15,2
        0.5,3200,70,14
        """
        let session = try CSVImporter().session(from: csv)
        XCTAssertEqual(session.channels[0].id, "rpm")   // "RPM" -> canonical rpm
        XCTAssertEqual(session.channels[1].id, "load")  // "Engine Load" -> load
        XCTAssertEqual(session.samples.count, 2)
        XCTAssertEqual(session.samples[1].value(.load), 70)
    }

    func testUnknownColumnBecomesCustomChannel() throws {
        let csv = "time,Widget Pressure (bar)\n0,1.2\n1,3.4"
        let session = try CSVImporter().session(from: csv)
        XCTAssertEqual(session.channels.count, 1)
        XCTAssertEqual(session.channels[0].name, "Widget Pressure")
        XCTAssertEqual(session.channels[0].unit, "bar")
        XCTAssertEqual(session.samples[1].value(channelID: session.channels[0].id), 3.4)
    }

    func testQuotedFieldsAndEmptyValues() throws {
        let csv = "time,\"Sensor, raw (mV)\",lambda\n0,10,\n1,20,0.8"
        let session = try CSVImporter().session(from: csv)
        XCTAssertEqual(session.channels[0].name, "Sensor, raw")
        XCTAssertNil(session.samples[0].value(.lambda)) // empty field skipped
        XCTAssertEqual(session.samples[1].value(.lambda), 0.8)
    }

    func testEmptyThrows() {
        XCTAssertThrowsError(try CSVImporter().session(from: "time,rpm"))
    }
}
