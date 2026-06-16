import XCTest
@testable import AtlasTuneCore

final class IdentificationTests: XCTestCase {
    func testIdentifiesMatchingImage() {
        let identifier = ROMIdentifier(packages: [Fixtures.package()])
        let match = identifier.identify(Fixtures.blankImage())
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.identity.family, "TestFamily")
        XCTAssertEqual(match?.identity.confidence, 1.0)
    }

    func testRejectsWrongSize() {
        let identifier = ROMIdentifier(packages: [Fixtures.package()])
        let small = BINImage(bytes: Data(repeating: 0, count: 8))
        XCTAssertNil(identifier.identify(small))
    }

    func testRejectsMissingSignature() {
        let identifier = ROMIdentifier(packages: [Fixtures.package()])
        let blank = BINImage(bytes: Data(repeating: 0, count: Fixtures.imageSize))
        // Right size, no signature -> zero confidence -> no match.
        XCTAssertNil(identifier.identify(blank))
    }

    func testProjectOpensFromCatalog() {
        let catalog = DefinitionCatalog(packages: [Fixtures.package()])
        let project = CalibrationProject.open(image: Fixtures.loadedImage(), catalog: catalog)
        XCTAssertNotNil(project)
        XCTAssertEqual(project?.revisions.roots.first?.name, "Stock")
    }
}
