import XCTest
@testable import AtlasTuneCore

final class DifferenceEngineTests: XCTestCase {
    func testIdenticalImagesProduceNoChanges() {
        let engine = DifferenceEngine()
        let image = Fixtures.loadedImage()
        let diff = engine.compare(image, image, using: Fixtures.package())
        XCTAssertTrue(diff.isIdentical)
        XCTAssertEqual(diff.totalChangedCells, 0)
    }

    func testDetectsEditedCells() throws {
        let accessor = TableAccessor()
        let before = Fixtures.loadedImage()
        var table = try accessor.read(Fixtures.table3D, from: before)
        table.setValue(25, row: 1, column: 1)
        let after = try accessor.write(table, into: before)

        let diff = DifferenceEngine().compare(before, after, using: Fixtures.package())
        XCTAssertFalse(diff.isIdentical)
        XCTAssertEqual(diff.totalChangedCells, 1)

        let tableDiff = diff.changedTables.first { $0.tableID == "t.map" }
        XCTAssertEqual(tableDiff?.cells.first?.row, 1)
        XCTAssertEqual(tableDiff?.cells.first?.column, 1)
        XCTAssertEqual(tableDiff?.cells.first?.after, 25)
    }

    func testProjectRevisionDifference() throws {
        let catalog = DefinitionCatalog(packages: [Fixtures.package()])
        var project = try XCTUnwrap(CalibrationProject.open(image: Fixtures.loadedImage(), catalog: catalog))
        let stockID = try XCTUnwrap(project.revisions.roots.first?.id)

        try project.applyEdit(.add(5), region: CellRegion(row: 0, column: 0), toTableID: "t.map")
        let rev = project.saveRevision(name: "Rev 1")

        let diff = try XCTUnwrap(project.difference(from: stockID, to: rev.id))
        XCTAssertEqual(diff.totalChangedCells, 1)
    }
}
