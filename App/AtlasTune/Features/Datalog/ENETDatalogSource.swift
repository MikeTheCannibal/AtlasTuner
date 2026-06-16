import Foundation
import AtlasTuneCore

/// Live datalog source over a BMW ENET (Ethernet) cable using DoIP + UDS. It connects via the
/// shared `DoIPClient`, optionally enters an extended session, then polls each mapped signal's RAM
/// address with ReadMemoryByAddress and decodes the bytes into `LogSample`s. Conforms to
/// `DatalogSource`, so it flows into the same pipeline as the demo and replay sources.
///
/// The channel map (`ENETChannelMap.s58FromA2L`) is sourced from the vehicle A2L; see Docs for the
/// software-variant caveat. This is read-only — Atlas Tune never writes to the ECU.
final class ENETDatalogSource: DatalogSource, @unchecked Sendable {
    let map: ENETChannelMap
    var channels: [LogChannel] { map.channels }

    private let host: String
    private let port: UInt16
    private let rate: Double
    private let useExtendedSession: Bool

    private var client: DoIPClient?
    private var task: Task<Void, Never>?

    init(host: String,
         port: UInt16 = DoIP.defaultPort,
         map: ENETChannelMap = .s58FromA2L,
         rate: Double = 20,
         extendedSession: Bool = true) {
        self.host = host
        self.port = port
        self.map = map
        self.rate = rate
        self.useExtendedSession = extendedSession
    }

    func start() -> AsyncStream<LogSample> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else { continuation.finish(); return }
                do { try await self.run { continuation.yield($0) } }
                catch { /* connection ended or failed */ }
                continuation.finish()
            }
            self.task = task
            continuation.onTermination = { [weak self] _ in self?.stop() }
        }
    }

    func stop() {
        task?.cancel()
        client?.cancel()
        client = nil
    }

    private func run(yield: @escaping (LogSample) -> Void) async throws {
        let client = DoIPClient(host: host, port: port,
                                testerAddress: map.testerAddress, ecuAddress: map.ecuAddress)
        self.client = client
        try await client.connect()
        if useExtendedSession {
            _ = try? await client.request(UDS.sessionControlRequest(UDS.extendedSession))
        }

        let startTime = Date()
        let interval = rate > 0 ? UInt64(1_000_000_000 / rate) : 0
        let signals = map.signals

        while !Task.isCancelled {
            var responses: [UInt32: [UInt8]] = [:]
            for signal in signals {
                if Task.isCancelled { break }
                let request = UDS.readMemoryByAddressRequest(address: signal.address, size: signal.size)
                guard let uds = try? await client.request(request),
                      let data = UDS.readMemoryResponse(uds) else { continue }
                responses[signal.address] = data
            }
            let time = Date().timeIntervalSince(startTime)
            yield(ENETDecoder(map: map).sample(time: time, responses: responses))
            if interval > 0 { try? await Task.sleep(nanoseconds: interval) }
        }
    }
}
