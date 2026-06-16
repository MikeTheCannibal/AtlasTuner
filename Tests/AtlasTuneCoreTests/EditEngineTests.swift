import XCTest
@testable import AtlasTuneCore

final class EditEngineTests: XCTestCase {
    let engine = EditEngine()
    let accessor = TableAccessor()

    private func table() throws -> CalibrationTable {
        try accessor.read(Fixtures.table3D, from: Fixtures.loadedImage())
    }

    func testAddToRegion() throws {
        let t = try table()
        let region = CellRegion(rows: 0..<1, columns: 0..<4)
        let result = engine.apply(.add(2), to: t, region: region)
        XCTAssertEqual(result.values[0][0], 3.0)
        XCTAssertEqual(result.values[0][3], 6.0)
        XCTAssertEqual(result.values[1][0], 5.0, "Unselected rows unchanged")
    }

    func testPercentChange() throws {
        let t = try table()
        let result = engine.apply(.percentChange(10), to: t, region: CellRegion(row: 0, column: 0))
        XCTAssertEqual(result.values[0][0], 1.1, accuracy: 1e-9)
    }

    func testMultiplyAndDivideAreInverse() throws {
        let t = try table()
        let region = CellRegion.all(t)
        let doubled = engine.apply(.multiply(2), to: t, region: region)
        let restored = engine.apply(.divide(2), to: doubled, region: region)
        XCTAssertEqual(restored.values, t.values)
    }

    func testDivideByZeroIsNoOp() throws {
        let t = try table()
        let result = engine.apply(.divide(0), to: t, region: .all(t))
        XCTAssertEqual(result.values, t.values)
    }

    func testFlattenSetsMean() throws {
        let t = try table()
        let region = CellRegion(rows: 0..<1, columns: 0..<4) // values 1,2,3,4 -> mean 2.5
        let result = engine.apply(.flatten, to: t, region: region)
        for c in 0..<4 { XCTAssertEqual(result.values[0][c], 2.5, accuracy: 1e-9) }
    }

    func testSetRespectsValueRange() throws {
        let t = try table()
        let result = engine.apply(.set(100), to: t, region: CellRegion(row: 0, column: 0))
        XCTAssertEqual(result.values[0][0], 30, "Clamped to table max")
    }

    func testHorizontalInterpolation() throws {
        var t = try table()
        t.setValue(0, row: 0, column: 0)
        t.setValue(30, row: 0, column: 3)
        let result = engine.apply(.interpolate(.horizontal), to: t, region: CellRegion(rows: 0..<1, columns: 0..<4))
        XCTAssertEqual(result.values[0][0], 0, accuracy: 1e-9)
        XCTAssertEqual(result.values[0][1], 10, accuracy: 1e-9)
        XCTAssertEqual(result.values[0][2], 20, accuracy: 1e-9)
        XCTAssertEqual(result.values[0][3], 30, accuracy: 1e-9)
    }

    func testPaste() throws {
        let t = try table()
        let result = engine.apply(.paste([[7, 8], [9, 10]]), to: t, region: CellRegion(row: 0, column: 0))
        XCTAssertEqual(result.values[0][0], 7)
        XCTAssertEqual(result.values[0][1], 8)
        XCTAssertEqual(result.values[1][0], 9)
        XCTAssertEqual(result.values[1][1], 10)
    }
}
