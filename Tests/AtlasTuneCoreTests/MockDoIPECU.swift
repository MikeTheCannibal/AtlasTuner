import Foundation
@testable import AtlasTuneCore

/// An in-memory DoIP ECU used to exercise the full live pipeline without hardware. It speaks just
/// enough ISO 13400/14229 to answer routing activation and `ReadDataByIdentifier`: on `send` it
/// decodes the client's frames and enqueues the matching responses (an ack then the data), which
/// `receive` delivers. Unknown DIDs get a `requestOutOfRange` negative response.
final class MockDoIPECU: ByteTransport, @unchecked Sendable {
    private let entityAddress: UInt16 = 0x1001
    private let testerAddress: UInt16 = 0x0E00
    private let values: [UInt16: [UInt8]]
    private let activationCode: UInt8

    private let lock = NSLock()
    private var outbox: [UInt8] = []
    private var waiter: CheckedContinuation<[UInt8], Error>?
    private var activated = false

    init(values: [UInt16: [UInt8]], activationCode: UInt8 = 0x10) {
        self.values = values
        self.activationCode = activationCode
    }

    var didActivate: Bool { lock.lock(); defer { lock.unlock() }; return activated }

    func open() async throws {}
    func close() {}

    func send(_ bytes: [UInt8]) async throws {
        var buffer = bytes
        while let framed = DoIPMessage.framedLength(buffer), buffer.count >= framed {
            let (message, consumed) = try DoIPMessage.decode(buffer)
            buffer.removeFirst(consumed)
            enqueue(respond(to: message))
        }
    }

    func receive() async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if !outbox.isEmpty {
                let out = outbox; outbox = []
                lock.unlock()
                continuation.resume(returning: out)
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }

    // MARK: ECU behaviour

    private func respond(to message: DoIPMessage) -> [[UInt8]] {
        switch message.payloadType {
        case .routingActivationRequest:
            if activationCode == 0x10 { lock.lock(); activated = true; lock.unlock() }
            let payload: [UInt8] = [
                UInt8(testerAddress >> 8), UInt8(testerAddress & 0xFF),
                UInt8(entityAddress >> 8), UInt8(entityAddress & 0xFF),
                activationCode, 0, 0, 0, 0,
            ]
            return [DoIPMessage(payloadType: .routingActivationResponse, payload: payload).encoded()]

        case .diagnosticMessage:
            guard let uds = message.diagnosticUDS(), uds.count >= 3, uds[0] == UDSService.readDataByIdentifier else {
                return []
            }
            let did = UInt16(uds[1]) << 8 | UInt16(uds[2])
            let ack = DoIPMessage(payloadType: .diagnosticMessagePositiveAck,
                                  payload: [UInt8(entityAddress >> 8), UInt8(entityAddress & 0xFF),
                                            UInt8(testerAddress >> 8), UInt8(testerAddress & 0xFF), 0x00]).encoded()
            let udsResponse: [UInt8]
            if let data = values[did] {
                udsResponse = [0x62, uds[1], uds[2]] + data
            } else {
                udsResponse = [0x7F, UDSService.readDataByIdentifier, 0x31]   // requestOutOfRange
            }
            let dataFrame = DoIPMessage.diagnostic(source: entityAddress, target: testerAddress, uds: udsResponse).encoded()
            return [ack, dataFrame]

        default:
            return []
        }
    }

    private func enqueue(_ frames: [[UInt8]]) {
        guard !frames.isEmpty else { return }
        lock.lock()
        for frame in frames { outbox += frame }
        if let continuation = waiter, !outbox.isEmpty {
            waiter = nil
            let out = outbox; outbox = []
            lock.unlock()
            continuation.resume(returning: out)
        } else {
            lock.unlock()
        }
    }
}
