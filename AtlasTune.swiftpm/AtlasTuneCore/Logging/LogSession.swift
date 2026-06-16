import Foundation

/// A recorded or live datalog session: its channels plus an ordered list of samples.
public struct LogSession: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var startedAt: Date
    public var channels: [LogChannel]
    public private(set) var samples: [LogSample]

    public init(
        id: UUID = UUID(),
        name: String,
        startedAt: Date = Date(),
        channels: [LogChannel] = LogChannel.s58Standard,
        samples: [LogSample] = []
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.channels = channels
        self.samples = samples
    }

    public mutating func append(_ sample: LogSample) {
        samples.append(sample)
    }

    public var duration: TimeInterval { samples.last?.time ?? 0 }
    public var sampleCount: Int { samples.count }

    /// Effective sample rate in Hz across the session.
    public var averageRate: Double {
        guard duration > 0 else { return 0 }
        return Double(samples.count - 1) / duration
    }

    /// All values for one channel, in time order (missing readings dropped).
    public func series(_ channel: LogChannel) -> [(time: TimeInterval, value: Double)] {
        samples.compactMap { s in s.value(channel).map { (s.time, $0) } }
    }
}
