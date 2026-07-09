import XCTest
@testable import AtlasTuneCore

final class ChecksumTests: XCTestCase {
    private let check = Array("123456789".utf8)

    // MARK: ParametricCRC known-answer vectors (CRC RevEng catalogue)

    func testPresetCheckValues() {
        let expected: [String: UInt32] = [
            "crc32": 0xCBF4_3926,
            "crc32-bzip2": 0xFC89_1918,
            "crc32-mpeg2": 0x0376_E6E7,
            "crc32-posix": 0x765E_7680,
            "crc16-ccitt-false": 0x29B1,
            "crc16-arc": 0xBB3D,
        ]
        for (name, value) in expected {
            let parameters = try! XCTUnwrap(CRCParameters.presets[name])
            XCTAssertEqual(ParametricCRC.checksum(check, using: parameters), value, "preset \(name)")
        }
    }

    func testParametricMatchesExistingCRC32() {
        let bytes = (0..<1024).map { _ in UInt8.random(in: .min ... .max) }
        XCTAssertEqual(
            ParametricCRC.checksum(bytes, using: CRCParameters.presets["crc32"]!),
            CRC32.checksum(bytes)
        )
    }

    func testIncrementalUpdateEqualsOneShot() {
        var engine = ParametricCRC(CRCParameters.presets["crc32-bzip2"]!)
        engine.update(Array(check[0..<4]))
        engine.update(Array(check[4...]))
        XCTAssertEqual(engine.value, 0xFC89_1918)
    }

    func testMixedReflection() {
        // refin=false / refout=true and its mirror are exercised via reflected equivalence:
        // reflecting the output of a non-reflected CRC must equal the mixed-mode result.
        let base = CRCParameters(width: 32, polynomial: 0x04C1_1DB7, initialValue: 0xFFFF_FFFF,
                                 xorOut: 0, reflectInput: false, reflectOutput: false)
        let mixed = CRCParameters(width: 32, polynomial: 0x04C1_1DB7, initialValue: 0xFFFF_FFFF,
                                  xorOut: 0, reflectInput: false, reflectOutput: true)
        let normal = ParametricCRC.checksum(check, using: base)
        var reflected: UInt32 = 0
        var input = normal
        for _ in 0..<32 { reflected = (reflected << 1) | (input & 1); input >>= 1 }
        XCTAssertEqual(ParametricCRC.checksum(check, using: mixed), reflected)
    }

    // MARK: Scheme strategy

    /// 256-byte image, one block protecting two ranges around a 4-byte checksum hole at 0x80.
    private func makeFixture(algorithm: ChecksumAlgorithm = .preset("crc32"),
                             storedByteOrder: ByteOrder? = nil) -> (BINImage, SchemeChecksumStrategy) {
        var data = Data(count: 256)
        for i in 0..<256 { data[i] = UInt8(i) }
        let image = BINImage(bytes: data, byteOrder: .littleEndian)
        let scheme = ChecksumScheme(blocks: [
            ChecksumBlock(
                name: "Test block",
                ranges: [ByteSpan(start: 0, length: 0x80), ByteSpan(start: 0x84, length: 256 - 0x84)],
                storedAt: 0x80,
                storedByteOrder: storedByteOrder,
                algorithm: algorithm
            ),
        ])
        return (image, SchemeChecksumStrategy(scheme: scheme))
    }

    func testVerifyFailsThenCorrectRepairs() throws {
        let (image, strategy) = makeFixture()
        XCTAssertEqual(strategy.verify(image).map(\.name), ["Test block"])

        let corrected = try strategy.correct(image)
        XCTAssertTrue(strategy.verify(corrected).isEmpty)

        // Only the stored checksum may change.
        let diff = zip(image.bytes, corrected.bytes).enumerated().filter { $1.0 != $1.1 }.map(\.offset)
        XCTAssertTrue(diff.allSatisfy { (0x80..<0x84).contains($0) })
    }

    func testEditInvalidatesCorrectedChecksum() throws {
        let (image, strategy) = makeFixture()
        var corrected = try strategy.correct(image)
        try corrected.writeBytes([0xAB], at: 0x10)
        XCTAssertFalse(strategy.verify(corrected).isEmpty)
    }

    func testBigEndianStorage() throws {
        let (image, strategy) = makeFixture(storedByteOrder: .bigEndian)
        let corrected = try strategy.correct(image)
        XCTAssertTrue(strategy.verify(corrected).isEmpty)

        let stored = try corrected.readBytes(at: 0x80, length: 4)
        var engine = ParametricCRC(CRCParameters.presets["crc32"]!)
        engine.update(try corrected.readBytes(at: 0, length: 0x80))
        engine.update(try corrected.readBytes(at: 0x84, length: 256 - 0x84))
        let value = engine.value
        XCTAssertEqual(stored, [
            UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value),
        ])
    }

    func testCRC16Block() throws {
        let (image, strategy) = makeFixture(algorithm: .preset("crc16-ccitt-false"))
        let corrected = try strategy.correct(image)
        XCTAssertTrue(strategy.verify(corrected).isEmpty)
        // 16-bit checksum only touches two bytes of the four-byte hole.
        let diff = zip(image.bytes, corrected.bytes).enumerated().filter { $1.0 != $1.1 }.map(\.offset)
        XCTAssertTrue(diff.allSatisfy { (0x80..<0x82).contains($0) })
    }

    func testOutOfBoundsBlockFailsVerification() {
        let (image, _) = makeFixture()
        let scheme = ChecksumScheme(blocks: [
            ChecksumBlock(name: "Broken", ranges: [ByteSpan(start: 0, length: 512)],
                          storedAt: 0x80, algorithm: .preset("crc32")),
        ])
        XCTAssertEqual(SchemeChecksumStrategy(scheme: scheme).verify(image).count, 1)
    }

    // MARK: JSON

    func testAlgorithmDecodingFormats() throws {
        let preset = #"{"preset": "crc32-bzip2"}"#
        let custom = #"{"width": 32, "polynomial": "0x04C11DB7", "initialValue": "0xFFFFFFFF", "xorOut": 4294967295, "reflectInput": true, "reflectOutput": true}"#

        let decoded = try JSONDecoder().decode(ChecksumAlgorithm.self, from: Data(preset.utf8))
        XCTAssertEqual(decoded.parameters, CRCParameters.presets["crc32-bzip2"])

        let params = try JSONDecoder().decode(ChecksumAlgorithm.self, from: Data(custom.utf8)).parameters
        XCTAssertEqual(params, CRCParameters.presets["crc32"])
    }

    func testUnknownPresetThrows() {
        let json = #"{"preset": "crc99-made-up"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(ChecksumAlgorithm.self, from: Data(json.utf8)))
    }

    func testSchemeRoundTrip() throws {
        let (_, strategy) = makeFixture(storedByteOrder: .bigEndian)
        let encoded = try JSONEncoder().encode(strategy.scheme)
        let decoded = try JSONDecoder().decode(ChecksumScheme.self, from: encoded)
        XCTAssertEqual(decoded, strategy.scheme)
    }

    func testPackageWithoutSchemeStillDecodes() throws {
        // The bundled S58 JSON predates the checksum field.
        let package = try XCTUnwrap(DefinitionCatalog.phase1.packages.first)
        XCTAssertNil(package.checksumScheme)
        XCTAssertNil(package.checksumStrategy)
    }

    // MARK: Integration: validator + exporter

    func testValidatorFlagsStaleChecksumAsWarning() throws {
        let (image, strategy) = makeFixture()
        var package = DefinitionPackage(
            id: "test", family: "Test", calibrationVersion: "1",
            expectedImageSizes: [image.size], checksumScheme: strategy.scheme
        )
        let stale = ExportValidator().validate(image, using: package)
        XCTAssertTrue(stale.isExportable, "stale checksums must not block export")
        XCTAssertTrue(stale.warnings.contains { $0.message.contains("Test block") })

        let corrected = try strategy.correct(image)
        let clean = ExportValidator().validate(corrected, using: package)
        XCTAssertTrue(clean.warnings.isEmpty)

        package.checksumScheme = nil
        XCTAssertTrue(ExportValidator().validate(image, using: package).warnings.isEmpty)
    }

    func testExportBINCorrectsChecksums() throws {
        let (image, strategy) = makeFixture()
        let data = try CalibrationExporter().exportBIN(image, checksum: strategy)
        XCTAssertTrue(strategy.verify(BINImage(bytes: data)).isEmpty)
    }
}
