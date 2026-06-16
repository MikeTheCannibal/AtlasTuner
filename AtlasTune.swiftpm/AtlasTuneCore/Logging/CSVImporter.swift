import Foundation

/// Parses CSV datalogs into a ``LogSession``. It round-trips with ``CSVExporter`` and is tolerant
/// of real-world logs (e.g. MHD / MHD+ exports): it strips a BOM, finds the time column by name
/// (falling back to the first column), accepts either seconds or `HH:MM:SS.fff` clock time, maps
/// column headers back to the canonical S58 channels by alias, and keeps every other column as a
/// custom channel. Duplicate canonical hits (e.g. "Boost" and "Boost Target") are de-duplicated so
/// channel ids stay unique.
public struct CSVImporter: Sendable {
    public init() {}

    public enum ImportError: Error, Equatable, Sendable {
        case empty
        case noChannels
    }

    public func session(from text: String, name: String = "Imported Log") throws -> LogSession {
        let rows = Self.parse(Self.stripBOM(text))
        guard let header = rows.first else { throw ImportError.empty }
        guard header.count >= 2 else { throw ImportError.noChannels }

        let timeIndex = Self.timeColumnIndex(header)
        let channelColumns = header.indices.filter { $0 != timeIndex }
        guard !channelColumns.isEmpty else { throw ImportError.noChannels }

        // Build channels with unique ids.
        var channels: [LogChannel] = []
        var usedIDs = Set<String>()
        var columnChannel: [Int: LogChannel] = [:]
        for column in channelColumns {
            var channel = Self.channel(forHeader: header[column])
            if usedIDs.contains(channel.id) {
                channel = LogChannel(id: Self.slug(header[column]) + "_\(column)",
                                     name: header[column].trimmingCharacters(in: .whitespaces),
                                     unit: channel.unit)
            }
            usedIDs.insert(channel.id)
            channels.append(channel)
            columnChannel[column] = channel
        }

        var samples: [LogSample] = []
        var baseClock: Double?
        for row in rows.dropFirst() {
            guard timeIndex < row.count, let time = Self.parseTime(row[timeIndex], base: &baseClock) else { continue }
            var values: [String: Double] = [:]
            for column in channelColumns {
                guard column < row.count, let channel = columnChannel[column] else { continue }
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

    // MARK: Time handling

    private static func timeColumnIndex(_ header: [String]) -> Int {
        let keys = ["time", "timestamp", "elapsed", "zeit"]
        for (i, h) in header.enumerated() where keys.contains(where: h.lowercased().contains) {
            return i
        }
        return 0
    }

    /// Parse a time field as seconds, or as a clock string converted to elapsed seconds.
    private static func parseTime(_ field: String, base: inout Double?) -> TimeInterval? {
        let trimmed = field.trimmingCharacters(in: .whitespaces)
        if let seconds = Double(trimmed) { return seconds }
        // HH:MM:SS.fff or MM:SS.fff
        let parts = trimmed.split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        let nums = parts.compactMap { $0 }
        var seconds = 0.0
        for n in nums { seconds = seconds * 60 + n }
        if base == nil { base = seconds }
        return seconds - (base ?? 0)
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
        let display = name.isEmpty ? header : name
        return LogChannel(id: slug(display), name: display, unit: unit)
    }

    private static func canonicalChannel(for name: String) -> LogChannel? {
        let key = name.lowercased()
        for (channel, aliases) in aliases where aliases.contains(where: key.contains) {
            return channel
        }
        return nil
    }

    /// Alias substrings, ordered so more specific channels are not preempted by generic tokens.
    private static let aliases: [(LogChannel, [String])] = [
        (.rpm, ["engine speed", "rpm", "drehzahl", "engine rpm"]),
        (.ignitionTiming, ["ignition", "timing", "spark", "zünd", "zuend", "advance"]),
        (.knock, ["knock", "klopf"]),
        (.wgdc, ["wastegate", "wgdc", "wg position", "wg duty"]),
        (.iat, ["intake air", "charge air temp", "inlet air", "iat", "air temp"]),
        (.coolant, ["coolant", "water temp", "engine temp", "wasser", "ect"]),
        (.lambda, ["lambda", "afr", "air/fuel", "air fuel"]),
        (.boost, ["boost", "ladedruck", "manifold pressure", "charge pressure", "map "]),
        (.fuelTrim, ["fuel trim", "stft", "ltft", "trim"]),
        (.load, ["load", "last", "füllung", "fuellung"]),
        (.torque, ["torque", "moment"]),
    ]

    private static func slug(_ s: String) -> String {
        let lowered = s.lowercased()
        return String(lowered.map { ($0.isLetter || $0.isNumber) ? $0 : "_" })
    }

    private static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
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
                case "\r": break
                default: field.append(ch)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }
}
