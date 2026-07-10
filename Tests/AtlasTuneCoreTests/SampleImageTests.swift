import XCTest
@testable import AtlasTuneCore

final class SampleImageTests: XCTestCase {
    func testSampleImageIdentifiesAsPhase1S58() throws {
        let project = try XCTUnwrap(CalibrationProject.open(image: SampleImage.s58()))
        XCTAssertEqual(project.package.id, "bmw.s58.mg1cs049.cb011")
        XCTAssertEqual(project.identity.confidence, 1.0)
        XCTAssertEqual(project.identity.calibrationVersion, "CB_011_253.23.0_1.2.0")
    }

    func testEveryTableIsReadableAndExplorable() throws {
        let project = try XCTUnwrap(CalibrationProject.open(image: SampleImage.s58()))
        XCTAssertFalse(project.package.tables.isEmpty)

        var variedTables = 0
        for definition in project.package.tables {
            let table = try XCTUnwrap(project.table(id: definition.id))
            if definition.cellCount > 1, table.minValue != table.maxValue { variedTables += 1 }
            // Filled values must respect the declared safe range.
            if let range = definition.valueRange {
                for value in table.flatValues {
                    XCTAssertGreaterThanOrEqual(value, range.lowerBound - 1e-6, definition.name)
                    XCTAssertLessThanOrEqual(value, range.upperBound + 1e-6, definition.name)
                }
            }
        }
        // The whole point is exploration — the vast majority of multi-cell tables must have shape.
        let multiCell = project.package.tables.filter { $0.cellCount > 1 }.count  // definition.cellCount
        XCTAssertGreaterThan(variedTables, multiCell * 9 / 10,
                             "Most multi-cell tables should be filled with non-flat data")
    }

    func testSampleImageIsCorrectSize() {
        XCTAssertEqual(SampleImage.s58().size, 8 * 1024 * 1024)
    }
}
