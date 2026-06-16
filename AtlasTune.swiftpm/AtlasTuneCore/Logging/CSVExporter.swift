import Foundation

/// Serialises a ``LogSession`` to CSV with a `time` column followed by one column per channel.
public struct CSVExporter: Sendable {
    public init() {}

    public func csv(for session: LogSession) -> String {
        var lines: [String] = []
        let header = ["time"] + session.channels.map { "\($0.name) (\($0.unit))" }
        lines.append(header.map(escape).joined(separator: ","))

        for sample in session.samples {
            var row = [format(sample.time)]
            for channel in session.channels {
                if let value = sample.value(channel) {
                    row.append(format(value))
                } else {
                    row.append("")
                }
            }
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    public func data(for session: LogSession) -> Data {
        Data(csv(for: session).utf8)
    }

    private func format(_ value: Double) -> String {
        String(format: "%g", value)
    }

    private func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
