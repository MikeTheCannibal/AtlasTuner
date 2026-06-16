import Foundation

/// Abstraction over a source of live datalog samples. Keeping the logging layer behind a
/// protocol means a Bluetooth/OBD adapter, a Wi-Fi bridge, or a replay file are all
/// interchangeable to the rest of the app.
public protocol DatalogSource: Sendable {
    /// Channels this source can provide.
    var channels: [LogChannel] { get }
    /// Begin streaming. The stream finishes when logging stops or the source disconnects.
    func start() -> AsyncStream<LogSample>
    /// Stop streaming and release any hardware resources.
    func stop()
}

/// A deterministic in-memory source that replays a recorded ``LogSession`` at a chosen rate.
/// Useful for previews, tests, and demoing the active-cell tracker without hardware.
public final class ReplayDatalogSource: DatalogSource, @unchecked Sendable {
    public let channels: [LogChannel]
    private let samples: [LogSample]
    private let rate: Double
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    public init(session: LogSession, rate: Double = 100) {
        self.channels = session.channels
        self.samples = session.samples
        self.rate = rate
    }

    public func start() -> AsyncStream<LogSample> {
        AsyncStream { continuation in
            let task = Task { [samples, rate] in
                let interval = rate > 0 ? UInt64(1_000_000_000 / rate) : 0
                for sample in samples {
                    if Task.isCancelled { break }
                    continuation.yield(sample)
                    if interval > 0 { try? await Task.sleep(nanoseconds: interval) }
                }
                continuation.finish()
            }
            lock.lock(); self.task = task; lock.unlock()
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func stop() {
        lock.lock(); task?.cancel(); task = nil; lock.unlock()
    }
}
