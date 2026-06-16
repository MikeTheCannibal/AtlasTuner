import Foundation
import AtlasTuneCore

/// Reads (downloads) the calibration image from the vehicle over DoIP/UDS by chunked
/// ReadMemoryByAddress, assembling a 1:1 `BINImage`. Reports progress as it streams, then the
/// finished image.
///
/// Reading protected flash requires a security-access unlock; the S58 seed→key algorithm is
/// proprietary and not bundled — supply one via `SecurityAccessProvider`. Without it, the ECU
/// returns "security access denied" and the read surfaces `ReadError.accessDenied`.
final class VehicleROMReader: @unchecked Sendable {
    enum Event: Sendable {
        case progress(fraction: Double, bytesReceived: Int, total: Int)
        case completed(BINImage)
    }
    enum ReadError: Error { case accessDenied(nrc: UInt8), incompleteRead, securityFailed }

    private let host: String
    private let port: UInt16
    private let layout: ROMLayout
    private let chunkSize: Int
    private let testerAddress: UInt16
    private let ecuAddress: UInt16
    private let security: SecurityAccessProvider

    private var client: DoIPClient?
    private var task: Task<Void, Never>?

    init(host: String,
         port: UInt16 = DoIP.defaultPort,
         layout: ROMLayout = .s58(),
         chunkSize: Int = 0x400,
         testerAddress: UInt16 = 0x0E00,
         ecuAddress: UInt16 = 0x0010,
         security: SecurityAccessProvider = NoSecurityAccess()) {
        self.host = host
        self.port = port
        self.layout = layout
        self.chunkSize = chunkSize
        self.testerAddress = testerAddress
        self.ecuAddress = ecuAddress
        self.security = security
    }

    func read() -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else { continuation.finish(); return }
                do {
                    try await self.run { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            self.task = task
            continuation.onTermination = { [weak self] _ in self?.cancel() }
        }
    }

    func cancel() {
        task?.cancel()
        client?.cancel()
        client = nil
    }

    private func run(yield: (Event) -> Void) async throws {
        let client = DoIPClient(host: host, port: port, testerAddress: testerAddress, ecuAddress: ecuAddress)
        self.client = client
        try await client.connect()
        _ = try? await client.request(UDS.sessionControlRequest(UDS.extendedSession))
        try await unlockIfNeeded(client)

        let plan = ROMReadPlan(layout: layout, chunkSize: chunkSize)
        var assembler = ROMAssembler(totalBytes: plan.totalBytes)

        for (index, chunk) in plan.chunks.enumerated() {
            if Task.isCancelled { throw CancellationError() }
            let request = UDS.readMemoryByAddressRequest(address: chunk.address, length: chunk.length)
            let uds = try await client.request(request)
            guard let data = UDS.readMemoryResponse(uds) else {
                if let parsed = UDS.parse(uds), case let .negative(_, code) = parsed {
                    throw ReadError.accessDenied(nrc: code)
                }
                throw ReadError.incompleteRead
            }
            assembler.place(data, at: chunk.imageOffset)
            // Throttle progress events (~every 32 chunks) to keep the UI light.
            if index % 32 == 0 || index == plan.chunks.count - 1 {
                yield(.progress(fraction: assembler.progress,
                                bytesReceived: assembler.bytesReceived, total: assembler.totalBytes))
            }
        }
        guard assembler.isComplete else { throw ReadError.incompleteRead }
        yield(.completed(assembler.image()))
    }

    private func unlockIfNeeded(_ client: DoIPClient) async throws {
        if security is NoSecurityAccess { return }
        let seedResponse = try await client.request(UDS.securityRequestSeed(level: security.level))
        guard let seed = UDS.securitySeedResponse(seedResponse)?.seed else { throw ReadError.securityFailed }
        if seed.allSatisfy({ $0 == 0 }) { return } // already unlocked
        let key = security.key(forSeed: seed)
        let keyResponse = try await client.request(UDS.securitySendKey(level: security.level, key: key))
        guard let parsed = UDS.parse(keyResponse), case .positive = parsed else {
            throw ReadError.securityFailed
        }
    }
}
