import XCTest
@testable import AtlasTuneCore

final class DoIPTests: XCTestCase {

    // MARK: DoIP framing

    func testGenericHeaderRoundTrip() throws {
        let message = DoIPMessage.diagnostic(source: 0x0E00, target: 0x1001, uds: [0x22, 0xF4, 0x0C])
        let bytes = message.encoded()
        // version, ~version, payload type 0x8001, length 0x00000007, then 4 addr + 3 uds
        XCTAssertEqual(Array(bytes[0..<2]), [0x02, 0xFD])
        XCTAssertEqual(Array(bytes[2..<4]), [0x80, 0x01])
        XCTAssertEqual(Array(bytes[4..<8]), [0x00, 0x00, 0x00, 0x07])

        let (decoded, consumed) = try DoIPMessage.decode(bytes)
        XCTAssertEqual(consumed, bytes.count)
        XCTAssertEqual(decoded, message)
        XCTAssertEqual(decoded.diagnosticUDS(), [0x22, 0xF4, 0x0C])
    }

    func testDecodeRejectsBadProtocol() {
        var bytes = DoIPMessage(payloadType: .aliveCheckRequest, payload: []).encoded()
        bytes[1] = 0x00    // corrupt the inverse-version check
        XCTAssertThrowsError(try DoIPMessage.decode(bytes)) {
            XCTAssertEqual($0 as? DoIPMessage.DecodeError, .protocolMismatch)
        }
    }

    func testFramedLengthAndTruncation() {
        let full = DoIPMessage(payloadType: .diagnosticMessage, payload: [1, 2, 3, 4, 5]).encoded()
        XCTAssertEqual(DoIPMessage.framedLength(full), full.count)
        XCTAssertNil(DoIPMessage.framedLength(Array(full.prefix(4))))     // header incomplete
        XCTAssertThrowsError(try DoIPMessage.decode(Array(full.prefix(full.count - 1)))) {
            guard case .truncatedPayload = ($0 as? DoIPMessage.DecodeError) else { return XCTFail() }
        }
    }

    func testRoutingActivationRequestAndResponse() throws {
        let request = DoIPMessage.routingActivation(sourceAddress: 0x0E00)
        XCTAssertEqual(request.payloadType, .routingActivationRequest)
        XCTAssertEqual(Array(request.payload[0..<2]), [0x0E, 0x00])
        XCTAssertEqual(request.payload.count, 7)   // 2 addr + 1 type + 4 reserved

        // Build a success response payload: tester, entity, code 0x10, reserved.
        var payload: [UInt8] = [0x0E, 0x00, 0x10, 0x01, 0x10, 0, 0, 0, 0]
        let response = DoIPMessage(payloadType: .routingActivationResponse, payload: payload)
        let result = try XCTUnwrap(response.routingActivationResult())
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.entityAddress, 0x1001)

        payload[4] = 0x06   // "routing activation denied"
        let denied = DoIPMessage(payloadType: .routingActivationResponse, payload: payload)
        XCTAssertFalse(try XCTUnwrap(denied.routingActivationResult()).isSuccess)
    }

    // MARK: UDS

    func testReadDataByIdentifierRequest() {
        XCTAssertEqual(UDSService.readDataByIdentifier(0xF40C), [0x22, 0xF4, 0x0C])
    }

    func testParsePositiveResponse() throws {
        let response = try UDSService.parse([0x62, 0xF4, 0x0C, 0x1A, 0xF0])
        XCTAssertEqual(response, .positive(did: 0xF40C, data: [0x1A, 0xF0]))
    }

    func testParseNegativeResponseAndPending() throws {
        let denied = try UDSService.parse([0x7F, 0x22, 0x33])
        XCTAssertEqual(denied, .negative(service: 0x22, code: .securityAccessDenied))
        let pending = try UDSService.parse([0x7F, 0x22, 0x78])
        guard case .negative(_, let code) = pending else { return XCTFail() }
        XCTAssertTrue(code.isResponsePending)
    }

    func testParseErrors() {
        XCTAssertThrowsError(try UDSService.parse([]))
        XCTAssertThrowsError(try UDSService.parse([0x62]))          // truncated positive
        XCTAssertThrowsError(try UDSService.parse([0x99, 0x00]))    // unexpected service
    }

    // MARK: Channel decoding

    func testDecodeBigEndianUInt16WithScaling() {
        let rpm = UDSDataIdentifier(channel: .rpm, did: 0xF40C, dataType: .uint16,
                                    scaling: Scaling(factor: 0.25, decimals: 0))
        // 0x1AF0 = 6896 raw → ×0.25 = 1724 rpm.
        XCTAssertEqual(try XCTUnwrap(LiveChannelDecoder().value(rpm, from: [0x1A, 0xF0])), 1724, accuracy: 1e-9)
    }

    func testDecodeWithOffsetAndBounds() {
        let iat = UDSDataIdentifier(channel: .iat, did: 0xF40F, byteOffset: 1, dataType: .uint8,
                                    scaling: Scaling(factor: 1, offset: -40, decimals: 0))
        XCTAssertEqual(LiveChannelDecoder().value(iat, from: [0x00, 0x50]), 40)   // 0x50=80, −40 = 40
        XCTAssertNil(LiveChannelDecoder().value(iat, from: [0x00]))               // too short
    }

    func testLittleEndianDecode() {
        let id = UDSDataIdentifier(channel: .torque, did: 0x1234, dataType: .uint16,
                                   byteOrder: .littleEndian, scaling: .identity)
        XCTAssertEqual(try XCTUnwrap(LiveChannelDecoder().value(id, from: [0xF0, 0x1A])), 6896)  // LE → 0x1AF0
    }

    // MARK: End-to-end against an in-memory mock ECU

    func testLiveSessionStreamsDecodedSamples() async throws {
        let ecu = MockDoIPECU(values: [0xF40C: [0x1A, 0xF0], 0xF404: [0x80]])   // rpm 1724, load ~50
        let set = LiveChannelSet(identifiers: [
            UDSDataIdentifier(channel: .rpm, did: 0xF40C, dataType: .uint16,
                              scaling: Scaling(factor: 0.25)),
            UDSDataIdentifier(channel: .load, did: 0xF404, dataType: .uint8,
                              scaling: Scaling(factor: 100.0 / 255.0)),
        ])
        let source = LiveDatalogSource(transport: ecu, channelSet: set, pollRate: 200)

        var collected: [LogSample] = []
        for await sample in source.start() {
            collected.append(sample)
            if collected.count >= 3 { source.stop(); break }
        }

        XCTAssertGreaterThanOrEqual(collected.count, 3)
        XCTAssertEqual(try XCTUnwrap(collected[0].value(.rpm)), 1724, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(collected[0].value(.load)), 128 * 100.0 / 255.0, accuracy: 1e-6)
        XCTAssertTrue(ecu.didActivate)
    }

    func testActivationFailurePropagates() async {
        let ecu = MockDoIPECU(values: [:], activationCode: 0x06)   // denied
        let source = LiveDatalogSource(transport: ecu, channelSet: .init(identifiers: []), pollRate: 100)
        var count = 0
        for await _ in source.start() { count += 1; if count > 2 { break } }
        XCTAssertEqual(count, 0)   // stream finishes immediately when activation is refused
    }
}
