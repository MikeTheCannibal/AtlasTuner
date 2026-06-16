import XCTest
@testable import AtlasTuneCore

final class ENETFramingTests: XCTestCase {
    // MARK: DoIP

    func testFrameHeaderAndLength() {
        let frame = DoIP.frame(type: 0x8001, payload: [0xAA, 0xBB])
        XCTAssertEqual(frame[0], 0x02)            // protocol version
        XCTAssertEqual(frame[1], 0xFD)            // inverse
        XCTAssertEqual(Array(frame[2...3]), [0x80, 0x01])
        XCTAssertEqual(Array(frame[4...7]), [0, 0, 0, 2])
        XCTAssertEqual(Array(frame[8...]), [0xAA, 0xBB])
    }

    func testRoundTripParse() {
        let frame = DoIP.diagnosticMessage(source: 0x0E00, target: 0x0010,
                                           uds: UDS.readDataByIdentifierRequest(0xF40C))
        let parsed = DoIP.parse(frame)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.consumed, frame.count)
        XCTAssertEqual(parsed?.message.type, 0x8001)
        let uds = DoIP.udsBytes(fromDiagnosticPayload: parsed!.message.payload)
        XCTAssertEqual(uds, [0x22, 0xF4, 0x0C])
    }

    func testParseNeedsFullFrame() {
        let frame = DoIP.frame(type: 0x0006, payload: [1, 2, 3, 4, 5])
        XCTAssertNil(DoIP.parse(Array(frame.prefix(6))))     // header incomplete
        XCTAssertNil(DoIP.parse(Array(frame.prefix(10))))    // payload incomplete
        XCTAssertNotNil(DoIP.parse(frame))
    }

    func testRoutingActivationSuccessDetection() {
        // type 0x0006, payload: testerAddr(2)+ecuAddr(2)+responseCode(1)=0x10
        let ok = DoIP.Message(type: 0x0006, payload: [0x0E, 0x00, 0x00, 0x10, 0x10])
        XCTAssertTrue(DoIP.isRoutingActivationSuccess(ok))
        let bad = DoIP.Message(type: 0x0006, payload: [0x0E, 0x00, 0x00, 0x10, 0x00])
        XCTAssertFalse(DoIP.isRoutingActivationSuccess(bad))
    }

    // MARK: UDS

    func testReadMemoryByAddressRequest() {
        // 4-byte address + 1-byte size: 0x23, ALFID 0x14, addr(BE), size.
        let req = UDS.readMemoryByAddressRequest(address: 0x500020E6, size: 2)
        XCTAssertEqual(req, [0x23, 0x14, 0x50, 0x00, 0x20, 0xE6, 0x02])
    }

    func testReadMemoryResponseParsing() {
        let data = UDS.readMemoryResponse([0x63, 0x58, 0x1B])   // 0x63 = 0x23 + 0x40
        XCTAssertEqual(data, [0x58, 0x1B])
        XCTAssertNil(UDS.readMemoryResponse([0x62, 0x00]))      // wrong service
    }

    func testNegativeResponse() {
        let r = UDS.parse([0x7F, 0x23, 0x78])
        XCTAssertEqual(r, .negative(service: 0x23, code: 0x78))
        XCTAssertTrue(UDS.isResponsePending(r!))
    }

    // MARK: Decoder (little-endian RAM reads, A2L-sourced map)

    func testDecoderProducesScaledSample() {
        let map = ENETChannelMap.s58FromA2L
        // Epm_nEng @ 0x500020E6, int16 *0.5, little-endian. 7000 raw (0x1B58) -> 3500 rpm.
        let responses: [UInt32: [UInt8]] = [0x500020E6: [0x58, 0x1B]]
        let sample = ENETDecoder(map: map).sample(time: 1.5, responses: responses)
        XCTAssertEqual(sample.time, 1.5)
        XCTAssertEqual(sample.value(.rpm), 3500)
        XCTAssertNil(sample.value(.coolant)) // address not in responses
    }

    func testLoadScalingMatchesA2L() {
        // AirMod_ratChrgAirCyl factor = 3/128 = 0.0234375 (matches the A2L "q0p0234" name).
        let map = ENETChannelMap.s58FromA2L
        let responses: [UInt32: [UInt8]] = [0x5002493A: [0x00, 0x10]] // 0x1000 = 4096 LE
        let sample = ENETDecoder(map: map).sample(time: 0, responses: responses)
        XCTAssertEqual(sample.value(.load) ?? 0, 4096 * 3.0 / 128.0, accuracy: 1e-6)
    }

    func testChannelMapAddressesUnique() {
        let addresses = ENETChannelMap.s58FromA2L.addresses
        XCTAssertEqual(addresses.count, Set(addresses).count)
        XCTAssertTrue(ENETChannelMap.s58FromA2L.channels.contains { $0.id == "rpm" })
        XCTAssertTrue(ENETChannelMap.s58FromA2L.channels.contains { $0.id == "load" })
    }
}
