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

    func testReadDataResponseParsing() {
        let response: [UInt8] = [0x62, 0xF4, 0x0C, 0x20, 0x00]   // 0x62 = 0x22 + 0x40
        let parsed = UDS.readDataResponse(response)
        XCTAssertEqual(parsed?.did, 0xF40C)
        XCTAssertEqual(parsed?.data, [0x20, 0x00])
    }

    func testNegativeResponse() {
        let r = UDS.parse([0x7F, 0x22, 0x78])
        XCTAssertEqual(r, .negative(service: 0x22, code: 0x78))
        XCTAssertTrue(UDS.isResponsePending(r!))
    }

    // MARK: Decoder

    func testDecoderProducesScaledSample() {
        let map = ENETChannelMap.s58Placeholder
        // RPM DID 0xF40C, uint16 *0.25 -> 0x2000 (8192) * 0.25 = 2048 rpm.
        let responses: [UInt16: [UInt8]] = [0xF40C: [0x20, 0x00]]
        let sample = ENETDecoder(map: map).sample(time: 1.5, responses: responses)
        XCTAssertEqual(sample.time, 1.5)
        XCTAssertEqual(sample.value(.rpm), 2048)
        XCTAssertNil(sample.value(.boost)) // DID not in responses
    }

    func testChannelMapDIDsUnique() {
        let dids = ENETChannelMap.s58Placeholder.dids
        XCTAssertEqual(dids.count, Set(dids).count)
    }
}
