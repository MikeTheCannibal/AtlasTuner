import XCTest
@testable import AtlasTuneCore

final class DIDReconnaissanceTests: XCTestCase {

    // MARK: DID scan against the mock ECU

    func testScanFindsRespondingDIDsAndWidths() async throws {
        let ecu = MockDoIPECU(values: [
            0xF40C: [0x3A, 0x98],        // 2-byte responder
            0xF404: [0x80],              // 1-byte responder
            0xF190: [1, 2, 3, 4],        // 4-byte responder
        ])
        let scanner = DIDScanner(client: DoIPClient(transport: ecu))
        let probes = try await scanner.scan(range: 0xF400...0xF410)

        // 0xF40C and 0xF404 are in range; 0xF190 is not.
        XCTAssertEqual(Set(probes.map(\.did)), [0xF40C, 0xF404])
        XCTAssertEqual(probes.first { $0.did == 0xF40C }?.byteLength, 2)
        XCTAssertEqual(probes.first { $0.did == 0xF404 }?.byteLength, 1)
        XCTAssertEqual(probes.first { $0.did == 0xF40C }?.sample, [0x3A, 0x98])
    }

    func testScanReportsProgressForEveryProbe() async throws {
        let ecu = MockDoIPECU(values: [0xF400: [0x01]])
        let scanner = DIDScanner(client: DoIPClient(transport: ecu))
        let counter = ProgressCounter()
        _ = try await scanner.scan(range: 0xF400...0xF404) { _, responders in
            counter.record(responders)                     // synchronous, thread-safe
        }
        // 5 DIDs probed; final responder count is 1.
        XCTAssertEqual(counter.calls, 5)
        XCTAssertEqual(counter.lastResponders, 1)
    }

    // MARK: Reconciler recovers a known map from synthetic capture

    /// Build a reference log and a raw capture where the true mapping and scaling are known, then
    /// assert the reconciler recovers them. rpm raw = value/0.25 (i.e. ×4); boost raw such that
    /// display = raw*0.0145 − 14.7.
    private func syntheticData(lag: TimeInterval) -> (LogSession, [CapturedDID]) {
        let dt = 0.1
        var refSamples: [LogSample] = []
        var rpmRaw: [TimedRaw] = []
        var boostRaw: [TimedRaw] = []
        var noiseRaw: [TimedRaw] = []
        for i in 0..<200 {
            let t = Double(i) * dt
            // A varied, non-degenerate drive so correlations are meaningful.
            let rpm = 1500 + 2500 * (1 + sin(t * 0.6)) + 200 * sin(t * 2.3)
            let boost = 6 + 10 * (1 + cos(t * 0.4)) / 2
            refSamples.append(LogSample(time: t, values: ["rpm": rpm, "boost": boost]))
            // Capture clock is shifted by `lag` relative to the reference.
            let ct = t + lag
            rpmRaw.append(TimedRaw(time: ct, raw: rpm / 0.25))
            boostRaw.append(TimedRaw(time: ct, raw: (boost + 14.7) / 0.0145))
            noiseRaw.append(TimedRaw(time: ct, raw: Double((i * 37) % 251)))  // unrelated DID
        }
        let reference = LogSession(name: "MHD", channels: [.rpm, .boost], samples: refSamples)
        let capture = [
            CapturedDID(did: 0xF40C, byteLength: 2, samples: rpmRaw),
            CapturedDID(did: 0xF40B, byteLength: 2, samples: boostRaw),
            CapturedDID(did: 0xDEAD, byteLength: 1, samples: noiseRaw),
        ]
        return (reference, capture)
    }

    func testReconcilerRecoversMapAndScaling() {
        let (reference, capture) = syntheticData(lag: 0)
        let candidates = DIDReconciler().reconcile(capture: capture, reference: reference)

        let rpm = try! XCTUnwrap(candidates.first { $0.channel.id == "rpm" })
        XCTAssertEqual(rpm.did, 0xF40C)
        XCTAssertGreaterThan(rpm.correlation, 0.99)
        XCTAssertEqual(rpm.scaling.factor, 0.25, accuracy: 1e-6)     // recovered ×0.25
        XCTAssertEqual(rpm.scaling.offset, 0, accuracy: 1e-6)

        let boost = try! XCTUnwrap(candidates.first { $0.channel.id == "boost" })
        XCTAssertEqual(boost.did, 0xF40B)
        XCTAssertEqual(boost.scaling.factor, 0.0145, accuracy: 1e-6)
        XCTAssertEqual(boost.scaling.offset, -14.7, accuracy: 1e-4)
        XCTAssertTrue(boost.isConfident)
    }

    func testReconcilerRecoversDespiteClockLag() {
        // Capture clock shifted +1.2s from the reference; alignment must find it.
        let (reference, capture) = syntheticData(lag: 1.2)
        let candidates = DIDReconciler().reconcile(capture: capture, reference: reference)
        let rpm = try! XCTUnwrap(candidates.first { $0.channel.id == "rpm" })
        XCTAssertEqual(rpm.did, 0xF40C)
        XCTAssertEqual(rpm.appliedLag, 1.2, accuracy: 0.1)          // lag recovered
        XCTAssertGreaterThan(rpm.correlation, 0.98)
        XCTAssertEqual(rpm.scaling.factor, 0.25, accuracy: 1e-3)
    }

    func testUnrelatedDIDIsNotMatched() {
        let (reference, capture) = syntheticData(lag: 0)
        let candidates = DIDReconciler().reconcile(capture: capture, reference: reference)
        // The noise DID 0xDEAD should never win a channel.
        XCTAssertFalse(candidates.contains { $0.did == 0xDEAD })
    }

    func testConstantDIDProducesNoCorrelation() {
        // A DID that never changes can't be reconciled (correlation undefined) and is dropped.
        let ref = LogSession(name: "r", channels: [.rpm], samples: (0..<10).map {
            LogSample(time: Double($0) * 0.1, values: ["rpm": 1000 + Double($0) * 100])
        })
        let flat = CapturedDID(did: 0x1234, byteLength: 2,
                               samples: (0..<10).map { TimedRaw(time: Double($0) * 0.1, raw: 42) })
        let candidates = DIDReconciler().reconcile(capture: [flat], reference: ref)
        XCTAssertTrue(candidates.isEmpty)
    }
}

/// Thread-safe synchronous counter for progress-callback invocations from the scan.
private final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    private var _lastResponders = 0
    var calls: Int { lock.lock(); defer { lock.unlock() }; return _calls }
    var lastResponders: Int { lock.lock(); defer { lock.unlock() }; return _lastResponders }
    func record(_ responders: Int) { lock.lock(); _calls += 1; _lastResponders = responders; lock.unlock() }
}
