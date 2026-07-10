import Foundation

/// A live ``DatalogSource`` backed by a DoIP diagnostic session. It activates the session, then
/// polls the configured DID set on a timer, yielding a `LogSample` per cycle into the same
/// `AsyncStream` the rest of the app already consumes — so the live heat map, active-cell tracker
/// and Atlas AI all work identically whether the data came from a CSV or a car.
public final class LiveDatalogSource: DatalogSource, @unchecked Sendable {
    public let channels: [LogChannel]

    private let client: DoIPClient
    private let identifiers: [UDSDataIdentifier]
    private let pollRate: Double
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - transport: the byte pipe (e.g. `TCPByteTransport` over Ethernet/RJ45, or a BLE adapter).
    ///   - channelSet: the DIDs to poll.
    ///   - pollRate: target samples per second (best-effort; bounded by round-trip latency).
    public init(transport: ByteTransport,
                channelSet: LiveChannelSet = .s58Placeholder,
                configuration: DoIPClient.Configuration = .init(),
                pollRate: Double = 20) {
        self.client = DoIPClient(transport: transport, configuration: configuration)
        self.identifiers = channelSet.identifiers
        self.channels = channelSet.channels
        self.pollRate = pollRate
    }

    public func start() -> AsyncStream<LogSample> {
        AsyncStream { continuation in
            let task = Task { [client, identifiers, pollRate] in
                do {
                    try await client.activate()
                } catch {
                    continuation.finish()   // couldn't stand up the session
                    return
                }
                let interval: UInt64 = pollRate > 0 ? UInt64(1_000_000_000 / pollRate) : 0
                let started = ContinuousClock.now
                while !Task.isCancelled {
                    let time = ContinuousClock.now - started
                    let seconds = Double(time.components.seconds) + Double(time.components.attoseconds) / 1e18
                    let sample = await client.sample(identifiers, at: seconds)
                    continuation.yield(sample)
                    if interval > 0 { try? await Task.sleep(nanoseconds: interval) }
                }
                await client.close()
                continuation.finish()
            }
            lock.lock(); self.task = task; lock.unlock()
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func stop() {
        lock.lock(); task?.cancel(); task = nil; lock.unlock()
        Task { await client.close() }
    }
}
