import XCTest
@testable import AtlasTuneCore

final class TableAccessorTests: XCTestCase {
    let accessor = TableAccessor()

    func testReadsRampValues() throws {
        let table = try accessor.read(Fixtures.table3D, from: Fixtures.loadedImage())
        XCTAssertEqual(table.rows, 3)
        XCTAssertEqual(table.columns, 4)
        XCTAssertEqual(table.values[0][0], 1.0, accuracy: 1e-9)
        XCTAssertEqual(table.values[2][3], 12.0, accuracy: 1e-9)
        XCTAssertEqual(table.xAxis, [1000, 2000, 3000, 4000])
        XCTAssertEqual(table.yAxis, [20, 40, 60])
    }

    func testWriteReadRoundTrip() throws {
        var table = try accessor.read(Fixtures.table3D, from: Fixtures.loadedImage())
        table.setValue(15.5, row: 1, column: 2)
        let image = try accessor.write(table, into: Fixtures.loadedImage())
        let reread = try accessor.read(Fixtures.table3D, from: image)
        XCTAssertEqual(reread.values[1][2], 15.5, accuracy: 1e-9)
    }

    func testWriteClampsToValueRange() throws {
        var table = try accessor.read(Fixtures.table3D, from: Fixtures.loadedImage())
        table.setValue(999, row: 0, column: 0) // range is 0...30
        XCTAssertEqual(table.values[0][0], 30)
    }

    func testScalingPrecisionPreserved() throws {
        var table = try accessor.read(Fixtures.table3D, from: Fixtures.loadedImage())
        table.setValue(2.5, row: 0, column: 1)
        let image = try accessor.write(table, into: Fixtures.loadedImage())
        XCTAssertEqual(try accessor.read(Fixtures.table3D, from: image).values[0][1], 2.5, accuracy: 1e-9)
    }
}
