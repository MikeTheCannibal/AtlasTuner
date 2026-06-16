import Foundation

/// Parses CSV datalogs into a ``LogSession``. It round-trips with ``CSVExporter`` and also accepts
/// generic logs (e.g. exported from another tool): the first column is treated as time and the
/// remaining columns become channels, mapped back to the canonical S58 channels by name/alias so
/// the active-cell tracker still recognises RPM and load.
public struct CSVImporter: Sendable {
    public init() {}

    public enum ImportError: Error, Equatable, Sendable {
        case empty
        case noChannels
    }

    public func session(from text: String, name: String = "Imported Log") throws -> LogSession {
        let rows = Self.parse(text)
        guard let header = rows.first else { throw ImportError.empty }
        guard header.count >= 2 else { throw ImportError.noChannels }

        // First column = time; the rest are channels.
        let channels = header.dropFirst().map(Self.channel(forHeader:))

        var samples: [LogSample] = []
        samples.reserveCapacity(rows.count - 1)
        for row in rows.dropFirst() {
            guard !row.isEmpty, let time = Double(row[0]) else { continue }
            var values: [String: Double] = [:]
            for (index, channel) in channels.enumerated() {
                let column = index + 1
                guard column < row.count else { continue }
                let field = row[column].trimmingCharacters(in: .whitespaces)
                if let value = Double(field) { values[channel.id] = value }
            }
            samples.append(LogSample(time: time, values: values))
        }
        guard !samples.isEmpty else { throw ImportError.empty }
        return LogSession(name: name, channels: channels, samples: samples)
    }

    public func session(from data: Data, name: String = "Imported Log") throws -> LogSession {
        try session(from: String(decoding: data, as: UTF8.self), name: name)
    }

    // MARK: Header → channel mapping

    private static func channel(forHeader header: String) -> LogChannel {
        var name = header.trimmingCharacters(in: .whitespaces)
        var unit = ""
        if name.hasSuffix(")"), let open = name.lastIndex(of: "(") {
            let inside = name[name.index(after: open)..<name.index(before: name.endIndex)]
            unit = inside.trimmingCharacters(in: .whitespaces)
            name = name[..<open].trimmingCharacters(in: .whitespaces)
        }
        if let known = canonicalChannel(for: name) { return known }
        let id = name.isEmpty ? header : name
        return LogChannel(id: slug(id), name: name.isEmpty ? header : name, unit: unit)
    }

    /// Map a column name to a canonical S58 channel by alias, preserving its stable id so the
    /// active-cell tracker (which keys on "rpm"/"load") keeps working on imported logs.
    private static func canonicalChannel(for name: String) -> LogChannel? {
        let key = name.lowercased()
        for (channel, aliases) in aliases where aliases.contains(where: key.contains) {
            return channel
        }
        return nil
    }

    private static let aliases: [(LogChannel, [String])] = [
        (.rpm, ["engine speed", "rpm", "drehzahl"]),
        (.load, ["engine load", "load", "last", "füllung", "fuellung", "charge"]),
        (.boost, ["boost", "ladedruck", "manifold pressure", "map "]),
        (.lambda, ["lambda", "afr", "air/fuel", "λ"]),
        (.ignitionTiming, ["ignition", "timing", "spark", "zünd", "zuend", "advance"]),
        (.knock, ["knock", "klopf"]),
        (.wgdc, ["wastegate", "wgdc", "duty"]),
        (.fuelTrim, ["fuel trim", "stft", "ltft", "trim"]),
        (.iat, ["intake air", "iat", "charge air temp"]),
        (.coolant, ["coolant", "ect", "wasser"]),
        (.torque, ["torque", "moment"]),
    ]

    private static func slug(_ s: String) -> String {
        let lowered = s.lowercased()
        let mapped = lowered.map { ($0.isLetter || $0.isNumber) ? $0 : "_" }
        return String(mapped)
    }

    // MARK: CSV tokenizer (handles quotes and "" escapes)

    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func nextChar() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }

        func endField() { row.append(field); field = "" }
        func endRow() { endField(); rows.append(row); row = [] }

        while let ch = nextChar() {
            if inQuotes {
                if ch == "\"" {
                    if let next = nextChar() {
                        if next == "\"" { field.append("\"") }
                        else { inQuotes = false; pending = next }
                    } else { inQuotes = false }
                } else { field.append(ch) }
            } else {
                switch ch {
                case "\"": inQuotes = true
                case ",": endField()
                case "\n": endRow()
                case "\r": break // handle \r\n and bare \r
                default: field.append(ch)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }
}
