import XCTest
@testable import AtlasTuneCore

final class VehicleReadTests: XCTestCase {
    // MARK: Read plan / assembler

    func testPlanChunksCoverLayoutExactly() {
        let layout = ROMLayout(imageSize: 1000,
                               regions: [MemoryRegion(name: "A", address: 0x8000, size: 1000, imageOffset: 0)])
        let plan = ROMReadPlan(layout: layout, chunkSize: 256)
        XCTAssertEqual(plan.totalBytes, 1000)
        XCTAssertEqual(plan.chunks.count, 4)               // 256+256+256+232
        XCTAssertEqual(plan.chunks.last?.length, 1000 - 256 * 3)
        // Addresses and offsets advance correctly.
        XCTAssertEqual(plan.chunks[1].address, 0x8000 + 256)
        XCTAssertEqual(plan.chunks[1].imageOffset, 256)
        XCTAssertEqual(plan.chunks.reduce(0) { $0 + $1.length }, 1000)
    }

    func testAssemblerReconstructsImageAndProgress() {
        let layout = ROMLayout(imageSize: 4,
                               regions: [MemoryRegion(name: "A", address: 0, size: 4, imageOffset: 0)])
        let plan = ROMReadPlan(layout: layout, chunkSize: 2)
        var assembler = ROMAssembler(totalBytes: plan.totalBytes)
        XCTAssertEqual(assembler.progress, 0)
        assembler.place([0xDE, 0xAD], at: plan.chunks[0].imageOffset)
        XCTAssertEqual(assembler.progress, 0.5, accuracy: 1e-9)
        assembler.place([0xBE, 0xEF], at: plan.chunks[1].imageOffset)
        XCTAssertTrue(assembler.isComplete)
        XCTAssertEqual(Array(assembler.image().bytes), [0xDE, 0xAD, 0xBE, 0xEF])
    }

    // MARK: UDS framing

    func testReadMemoryChunkAndUploadFraming() {
        XCTAssertEqual(UDS.readMemoryByAddressRequest(address: 0x80000000, size: 0x40),
                       [0x23, 0x14, 0x80, 0x00, 0x00, 0x00, 0x40])
        XCTAssertEqual(UDS.requestUploadRequest(address: 0x80000000, size: 0x800000),
                       [0x35, 0x00, 0x44, 0x80, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00, 0x00])
    }

    func testRequestUploadResponseMaxBlock() {
        // 0x75, lengthFormatId 0x20 (2 length bytes), 0x0102 = 258.
        XCTAssertEqual(UDS.requestUploadResponse([0x75, 0x20, 0x01, 0x02]), 258)
    }

    func testSecuritySeedAndKeyFraming() {
        XCTAssertEqual(UDS.securityRequestSeed(level: 0x11), [0x27, 0x11])
        XCTAssertEqual(UDS.securitySendKey(level: 0x11, key: [1, 2, 3, 4]), [0x27, 0x12, 1, 2, 3, 4])
        let seed = UDS.securitySeedResponse([0x67, 0x11, 0xAA, 0xBB])
        XCTAssertEqual(seed?.level, 0x11)
        XCTAssertEqual(seed?.seed, [0xAA, 0xBB])
    }

    func testTransferDataResponse() {
        let r = UDS.transferDataResponse([0x76, 0x01, 0x11, 0x22])
        XCTAssertEqual(r?.counter, 0x01)
        XCTAssertEqual(r?.data, [0x11, 0x22])
    }

    // MARK: Compare / verify

    func testWorkingMatchesAndDifferenceAgainstReference() throws {
        let catalog = DefinitionCatalog(packages: [Fixtures.package()])
        var project = try XCTUnwrap(CalibrationProject.open(image: Fixtures.loadedImage(), catalog: catalog))

        // Identical reference -> matches, no diff.
        XCTAssertTrue(project.workingMatches(Fixtures.loadedImage()))
        XCTAssertTrue(project.difference(against: Fixtures.loadedImage()).isIdentical)

        // After an edit, working no longer matches the (stock) reference, and the diff localises it.
        try project.applyEdit(.add(3), region: CellRegion(row: 0, column: 0), toTableID: "t.map")
        let stock = Fixtures.loadedImage()
        XCTAssertFalse(project.workingMatches(stock))
        XCTAssertEqual(project.difference(against: stock).totalChangedCells, 1)
    }
}
