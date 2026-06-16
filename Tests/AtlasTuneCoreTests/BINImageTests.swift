import XCTest
@testable import AtlasTuneCore

final class BINImageTests: XCTestCase {
    func testLittleEndianRoundTrip() throws {
        var image = BINImage(bytes: Data(repeating: 0, count: 16), byteOrder: .littleEndian)
        try image.writeRaw(0x1234, type: .uint16, at: 0)
        let bytes = try image.readBytes(at: 0, length: 2)
        XCTAssertEqual(bytes, [0x34, 0x12])
        XCTAssertEqual(try image.readRaw(.uint16, at: 0), 0x1234)
    }

    func testBigEndianRoundTrip() throws {
        var image = BINImage(bytes: Data(repeating: 0, count: 16), byteOrder: .bigEndian)
        try image.writeRaw(0x1234, type: .uint16, at: 0)
        let bytes = try image.readBytes(at: 0, length: 2)
        XCTAssertEqual(bytes, [0x12, 0x34])
        XCTAssertEqual(try image.readRaw(.uint16, at: 0), 0x1234)
    }

    func testSignedIntegerRoundTrip() throws {
        var image = BINImage(bytes: Data(repeating: 0, count: 16))
        try image.writeRaw(-5, type: .int16, at: 4)
        XCTAssertEqual(try image.readRaw(.int16, at: 4), -5)
    }

    func testFloat32RoundTrip() throws {
        var image = BINImage(bytes: Data(repeating: 0, count: 16))
        try image.writeRaw(3.14, type: .float32, at: 8)
        XCTAssertEqual(try image.readRaw(.float32, at: 8), Double(Float(3.14)), accuracy: 1e-6)
    }

    func testWriteClampsIntegerOverflow() throws {
        var image = BINImage(bytes: Data(repeating: 0, count: 4))
        try image.writeRaw(99999, type: .uint8, at: 0)
        XCTAssertEqual(try image.readRaw(.uint8, at: 0), 255)
    }

    func testOutOfBoundsThrows() {
        let image = BINImage(bytes: Data(repeating: 0, count: 4))
        XCTAssertThrowsError(try image.readBytes(at: 3, length: 4))
    }

    func testCopyOnWriteDoesNotMutateOriginal() throws {
        let original = BINImage(bytes: Data(repeating: 0, count: 8))
        var copy = original
        try copy.writeRaw(42, type: .uint8, at: 0)
        XCTAssertEqual(try original.readRaw(.uint8, at: 0), 0)
        XCTAssertEqual(try copy.readRaw(.uint8, at: 0), 42)
    }
}
