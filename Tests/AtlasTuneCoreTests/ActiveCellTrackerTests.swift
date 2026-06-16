import XCTest
@testable import AtlasTuneCore

final class ActiveCellTrackerTests: XCTestCase {
    private func table() throws -> CalibrationTable {
        try TableAccessor().read(Fixtures.table3D, from: Fixtures.loadedImage())
    }

    func testNearestIndexSnapping() {
        let axis = [1000.0, 2000, 3000, 4000]
        XCTAssertEqual(ActiveCellTracker.nearestIndex(of: 2100, in: axis), 1)
        XCTAssertEqual(ActiveCellTracker.nearestIndex(of: 2600, in: axis), 2)
        XCTAssertEqual(ActiveCellTracker.nearestIndex(of: 50, in: axis), 0)
        XCTAssertEqual(ActiveCellTracker.nearestIndex(of: 9999, in: axis), 3)
    }

    func testRecordMapsToCell() throws {
        var tracker = ActiveCellTracker(table: try table())
        let address = tracker.record(x: 3000, y: 40)
        XCTAssertEqual(address, CellAddress(row: 1, column: 2))
        XCTAssertEqual(tracker.current, CellAddress(row: 1, column: 2))
        XCTAssertEqual(tracker.hits[1][2], 1)
    }

    func testHeatMapNormalises() throws {
        var tracker = ActiveCellTracker(table: try table())
        for _ in 0..<4 { tracker.record(x: 1000, y: 20) } // cell (0,0) x4
        tracker.record(x: 4000, y: 60)                      // cell (2,3) x1
        let heat = tracker.heatMap()
        XCTAssertEqual(heat[0][0], 1.0, accuracy: 1e-9)
        XCTAssertEqual(heat[2][3], 0.25, accuracy: 1e-9)
        XCTAssertEqual(heat[1][1], 0.0)
    }

    func testRecentCellsOrdering() throws {
        var tracker = ActiveCellTracker(table: try table())
        tracker.record(x: 1000, y: 20)
        tracker.record(x: 2000, y: 40)
        tracker.record(x: 3000, y: 60)
        let recent = tracker.recentCells(2)
        XCTAssertEqual(recent.first, CellAddress(row: 2, column: 2))
        XCTAssertEqual(recent.count, 2)
    }

    func testTotalHits() throws {
        var tracker = ActiveCellTracker(table: try table())
        for _ in 0..<10 { tracker.record(x: 2000, y: 40) }
        XCTAssertEqual(tracker.totalHits, 10)
    }
}
