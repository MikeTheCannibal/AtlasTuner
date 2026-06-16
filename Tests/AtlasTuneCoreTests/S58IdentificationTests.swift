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
