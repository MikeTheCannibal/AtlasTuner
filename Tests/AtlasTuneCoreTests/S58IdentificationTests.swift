import XCTest
@testable import AtlasTuneCore

/// Verifies the shipped S58 package identifies a real G87 M2 / MG1CS049 image. We do not commit
/// the proprietary 8 MB dump (it embeds a VIN); instead we reconstruct an image of the correct
/// size with the exact identification bytes written at their real offsets, which exercises the
/// same `expectedImageSizes` + `signatures` + `versionField` configuration.
final class S58IdentificationTests: XCTestCase {

    /// Builds a minimal stand-in for the real MG1CS049 image: correct size + identification bytes.
    private func syntheticMG1CS049() -> BINImage {
        var image = BINImage(bytes: Data(repeating: 0, count: S58DefinitionPackage.imageSize),
                             byteOrder: .littleEndian)
        try! image.writeBytes(Array("CB_011_253.23.0_1.2.0".utf8), at: 0x29000)
        try! image.writeBytes(Array("#DME_86T0#CX#BTL#MDG1_I35UP".utf8), at: 0x5FE1E)
        try! image.writeBytes(Array("DME8.6.S_S58_G87".utf8), at: 0x7FFE51)
        return image
    }

    func testIdentifiesRealG87Image() {
        let match = DefinitionCatalog.phase1.identify(syntheticMG1CS049())
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.identity.family, "S58 / MG1CS049 (DME 8.6.S)")
        XCTAssertEqual(match?.identity.confidence, 1.0)
        XCTAssertEqual(match?.identity.calibrationVersion, "CB_011_253.23.0_1.2.0")
        XCTAssertEqual(match?.identity.imageSize, 8 * 1024 * 1024)
    }

    func testWrongSizeImageNotIdentified() {
        let small = BINImage(bytes: Data(repeating: 0, count: 4 * 1024 * 1024))
        XCTAssertNil(DefinitionCatalog.phase1.identify(small))
    }

    func testPartialSignatureLowersConfidence() {
        var image = BINImage(bytes: Data(repeating: 0, count: S58DefinitionPackage.imageSize))
        // Only one of the two signatures present.
        try! image.writeBytes(Array("DME8.6.S_S58_G87".utf8), at: 0x7FFE51)
        let match = DefinitionCatalog.phase1.identify(image)
        XCTAssertEqual(match?.identity.confidence, 0.5)
    }

    func testBundledPackageLoadsFullTableSet() throws {
        // phase1 prefers the JSON package generated from the MHD+ XDF.
        let package = try XCTUnwrap(DefinitionPackage.bundled(named: "s58_mg1cs049"))
        XCTAssertEqual(package.id, "bmw.s58.mg1cs049.cb011")
        XCTAssertGreaterThan(package.tables.count, 1000, "Expected the full XDF-derived table set")
        // Categories from the spec must all be represented.
        let cats = Set(package.tables.map(\.category))
        XCTAssertTrue(cats.contains(.boost))
        XCTAssertTrue(cats.contains(.fuel))
        XCTAssertTrue(cats.contains(.ignition))
    }

    /// These six oil-pressure breakpoint tables were unnamed ("(autogen)") in the bundled
    /// MHD+-derived XDF. Their real names were recovered by address-matching against a
    /// different S58 variant's XDF (F4C9L8R5B) whose titles are fully authored — the addresses
    /// and semantics agree cleanly, unlike several other candidate matches at the same addresses
    /// that turned out to name unrelated tables (a coincidental collision between variants), so
    /// only these were applied. See Docs/DefinitionEngine.md § Cross-variant name recovery.
    func testOilPressureTableNamesRecoveredFromRelatedVariant() throws {
        let package = try XCTUnwrap(DefinitionPackage.bundled(named: "s58_mg1cs049"))
        let expected: [String: String] = [
            "xdf0000": "Speed and oil temperature dependent factor for taking oil pressure offset into account X",
            "xdf0001": "Speed and oil temperature dependent factor for taking oil pressure offset into account Y",
            "xdf0003": "Load-dependent oil pressure setpoint offset X",
            "xdf0004": "Load-dependent oil pressure setpoint offset Y",
            "xdf0006": "Oil pressure setpoint for regulated oil pump X",
            "xdf0007": "Oil pressure setpoint for regulated oil pump Y",
        ]
        for (id, name) in expected {
            let table = try XCTUnwrap(package.table(id: id), "missing \(id)")
            XCTAssertEqual(table.name, name)
            XCTAssertFalse(table.name.contains("autogen"))
        }
    }

    func testProjectOpensRealImageWithAllTables() throws {
        let project = try XCTUnwrap(CalibrationProject.open(image: syntheticMG1CS049()))
        XCTAssertEqual(project.package.id, "bmw.s58.mg1cs049.cb011")
        XCTAssertFalse(project.package.tables.isEmpty)
        // Every defined table must be readable within the 8 MB image bounds.
        for definition in project.package.tables {
            XCTAssertNoThrow(try project.table(id: definition.id))
        }
    }
}
