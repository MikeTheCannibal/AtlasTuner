import Foundation

/// One time-stamped row of channel readings. `time` is seconds from session start.
public struct LogSample: Codable, Sendable, Equatable {
    public var time: TimeInterval
    public var values: [String: Double]

    public init(time: TimeInterval, values: [String: Double]) {
        self.time = time
        self.values = values
    }

    public func value(_ channel: LogChannel) -> Double? { values[channel.id] }
    public func value(channelID: String) -> Double? { values[channelID] }
}
