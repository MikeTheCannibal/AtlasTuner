import XCTest
@testable import AtlasTuneCore

final class SupportTests: XCTestCase {
    // MARK: Search

    func testSearchRanksNameMatchesHighest() {
        let index = TableSearchIndex(package: Fixtures.package())
        let results = index.search("map")
        XCTAssertEqual(results.first?.table.id, "t.map")
    }

    func testSearchByCategory() {
        let index = TableSearchIndex(package: Fixtures.package())
        let results = index.search("fuel")
        XCTAssertTrue(results.contains { $0.table.id == "t.scalar" })
    }

    func testEmptyQueryReturnsAllSorted() {
        let index = TableSearchIndex(package: Fixtures.package())
        XCTAssertEqual(index.search("").count, 2)
    }

    // MARK: CSV export

    func testCSVExportHasHeaderAndRows() {
        var session = LogSession(name: "Test", channels: [.rpm, .boost])
        session.append(LogSample(time: 0, values: ["rpm": 1000, "boost": 5]))
        session.append(LogSample(time: 0.1, values: ["rpm": 2000, "boost": 10]))
        let csv = CSVExporter().csv(for: session)
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("Engine Speed"))
        XCTAssertTrue(lines[1].contains("1000"))
    }

    func testSessionAverageRate() {
        var session = LogSession(name: "Test", channels: [.rpm])
        for i in 0..<101 { session.append(LogSample(time: Double(i) / 100, values: ["rpm": 1000])) }
        XCTAssertEqual(session.averageRate, 100, accuracy: 0.01)
    }

    // MARK: CRC32

    func testCRC32KnownVector() {
        // CRC32("123456789") == 0xCBF43926
        XCTAssertEqual(CRC32.checksum(Array("123456789".utf8)), 0xCBF4_3926)
    }

    // MARK: Validation

    func testValidationPassesForCleanImage() {
        let report = ExportValidator().validate(Fixtures.loadedImage(), using: Fixtures.package())
        XCTAssertTrue(report.isExportable)
    }

    func testValidationFlagsWrongSize() {
        let small = BINImage(bytes: Data(repeating: 0, count: 8))
        let report = ExportValidator().validate(small, using: Fixtures.package())
        XCTAssertFalse(report.isExportable)
    }

    // MARK: Revision package round trip

    func testRevisionPackageRoundTrip() throws {
        var tree = RevisionTree()
        tree.add(Revision(name: "Stock", image: Fixtures.loadedImage()))
        let data = try CalibrationExporter().exportRevisionPackage(
            tree, identity: ROMIdentity(family: "f", calibrationVersion: "1", imageSize: 64, confidence: 1),
            packageID: "test.pkg"
        )
        let decoded = try RevisionPackage.decode(data)
        XCTAssertEqual(decoded.revisions.count, 1)
        XCTAssertEqual(decoded.revisions.first?.name, "Stock")
    }
}
