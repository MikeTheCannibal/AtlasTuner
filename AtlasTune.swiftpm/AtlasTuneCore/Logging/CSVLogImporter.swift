import Foundation

/// Imports a datalog CSV exported by MHD, bootmod3, and similar BMW logging tools into a
/// ``LogSession``. Every such tool writes a header row plus comma-separated samples, but each
/// spells the channels differently ("RPM" vs "Engine Speed" vs "rpm", "Boost Pressure (psi)" vs
/// "boost_psi"). The importer parses the CSV robustly and maps recognised columns onto the
/// canonical S58 channel set so the active-cell tracker and heat map light up regardless of source;
/// unrecognised columns are preserved verbatim rather than dropped.
public struct CSVLogImporter: Sendable {
    public struct Options: Sendable {
        /// When set, columns recognised as air-fuel ratio are converted to lambda by dividing by
        /// this stoichiometric ratio (14.7 for pump gasoline) — but only if the log has no
        /// explicit lambda column. S58 fuelling maps are in lambda, so this keeps an AFR log
        /// aligned with the tables. Set to `nil` to keep AFR as its own channel.
        public var afrToLambdaStoich: Double?

        public init(afrToLambdaStoich: Double? = 14.7) {
            self.afrToLambdaStoich = afrToLambdaStoich
        }
    }

    public enum ImportError: Error, Equatable {
        case empty                 // no bytes / whitespace only
        case noColumns             // header row had no usable columns
        case noDataRows            // header parsed but no sample rows followed
    }

    public let options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    // MARK: Entry points

    public func session(from data: Data, name: String) throws -> LogSession {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.empty
        }
        return try session(from: text, name: name)
    }

    public func session(from text: String, name: String) throws -> LogSession {
        let rows = Self.parseCSV(text)
        guard let headerRow = rows.first(where: { !isBlank($0) }) else { throw ImportError.empty }
        let headerIndex = rows.firstIndex { !isBlank($0) }!
        let dataRows = rows[(headerIndex + 1)...].filter { !isBlank($0) }

        let columns = headerRow.map(Self.parseHeaderCell)
        guard !columns.isEmpty else { throw ImportError.noColumns }
        guard !dataRows.isEmpty else { throw ImportError.noDataRows }

        let plan = resolveColumns(columns)
        guard !plan.channelColumns.isEmpty else { throw ImportError.noColumns }

        var samples: [LogSample] = []
        samples.reserveCapacity(dataRows.count)
        for (rowIndex, row) in dataRows.enumerated() {
            var values: [String: Double] = [:]
            for col in plan.channelColumns where col.index < row.count {
                guard let raw = Self.number(row[col.index]) else { continue }
                values[col.channel.id] = col.transform(raw)
            }
            if values.isEmpty { continue }
            let time = plan.time(row: row, rowIndex: rowIndex)
            samples.append(LogSample(time: time, values: values))
        }
        guard !samples.isEmpty else { throw ImportError.noDataRows }

        return LogSession(
            name: name,
            channels: plan.channelColumns.map(\.channel),
            samples: samples
        )
    }

    // MARK: Column resolution

    private struct ResolvedColumn {
        let index: Int
        let channel: LogChannel
        let transform: @Sendable (Double) -> Double
    }

    private struct Plan {
        let channelColumns: [ResolvedColumn]
        let timeColumn: Int?
        let timeDivisor: Double

        /// Session-relative time in seconds for a row. Prefers a detected time column; otherwise
        /// synthesises a monotonic index (nominal 1 Hz — the heat map does not depend on it).
        func time(row: [String], rowIndex: Int) -> TimeInterval {
            if let timeColumn, timeColumn < row.count, let t = CSVLogImporter.number(row[timeColumn]) {
                return t / timeDivisor
            }
            return TimeInterval(rowIndex)
        }
    }

    private func resolveColumns(_ columns: [(name: String, unit: String)]) -> Plan {
        // Locate the time column first so it is never also emitted as a channel.
        var timeColumn: Int?
        var timeDivisor = 1.0
        for (i, column) in columns.enumerated() where Self.isTimeColumn(column.name) {
            timeColumn = i
            timeDivisor = Self.timeDivisor(forUnit: column.unit)
            break
        }

        let hasLambda = columns.contains { Self.canonicalID(name: $0.name) == LogChannel.lambda.id }

        var resolved: [ResolvedColumn] = []
        var usedIDs = Set<String>()
        for (i, column) in columns.enumerated() {
            if i == timeColumn { continue }

            // AFR → lambda, only when there is no explicit lambda column to defer to.
            if let stoich = options.afrToLambdaStoich, !hasLambda, Self.isAFR(column.name) {
                if usedIDs.insert(LogChannel.lambda.id).inserted {
                    resolved.append(ResolvedColumn(
                        index: i, channel: .lambda,
                        transform: { stoich != 0 ? $0 / stoich : $0 }
                    ))
                    continue
                }
            }

            let channel: LogChannel
            if let canonical = Self.canonicalChannel(name: column.name), !usedIDs.contains(canonical.id) {
                channel = canonical
            } else {
                channel = Self.preservedChannel(name: column.name, unit: column.unit, used: usedIDs)
            }
            usedIDs.insert(channel.id)
            resolved.append(ResolvedColumn(index: i, channel: channel, transform: { $0 }))
        }

        return Plan(channelColumns: resolved, timeColumn: timeColumn, timeDivisor: timeDivisor)
    }

    // MARK: Channel recognition

    /// The canonical S58 channel a header maps to, or `nil` if unrecognised.
    public static func canonicalChannel(name: String) -> LogChannel? {
        guard let id = canonicalID(name: name) else { return nil }
        return LogChannel.s58Standard.first { $0.id == id }
    }

    private static func canonicalID(name: String) -> String? {
        let key = normalize(name)
        for (id, aliases) in aliasTable where aliases.contains(key) {
            return id
        }
        return nil
    }

    private static func isAFR(_ name: String) -> Bool {
        afrAliases.contains(normalize(name))
    }

    private static func preservedChannel(name: String, unit: String, used: Set<String>) -> LogChannel {
        let base = slug(name).isEmpty ? "channel" : slug(name)
        var id = base
        var n = 2
        while used.contains(id) { id = "\(base)_\(n)"; n += 1 }
        let display = name.trimmingCharacters(in: .whitespaces)
        return LogChannel(id: id, name: display.isEmpty ? id : display, unit: unit)
    }

    /// normalized-header -> canonical channel id. Exact-match keeps distinct signals like
    /// "Boost" and "Boost Target" from colliding — the latter is unrecognised and preserved.
    private static let aliasTable: [(id: String, aliases: Set<String>)] = [
        (LogChannel.rpm.id, ["rpm", "enginespeed", "enginerpm", "engspeed", "revs", "rpmaverage"]),
        (LogChannel.load.id, ["load", "calcload", "calculatedload", "engineload", "rl",
                              "relativeload", "airload", "loadpct", "loadpercent"]),
        (LogChannel.boost.id, ["boost", "boostpressure", "boostactual", "boostpsi", "actualboost",
                              "chargepressure", "manifoldpressure", "boostbar"]),
        (LogChannel.lambda.id, ["lambda", "lambda1", "lambdaactual", "lam", "lambdaavg"]),
        (LogChannel.ignitionTiming.id, ["ignition", "ignitiontiming", "timing", "timingavg",
                              "ignitionangle", "spark", "sparkadvance", "ignavg", "ignitionavg",
                              "ignitiontimingavg", "iga"]),
        (LogChannel.knock.id, ["knock", "knockretard", "knocksum", "knockavg", "knockactivity",
                              "knockcount", "knocklevel"]),
        (LogChannel.wgdc.id, ["wastegate", "wastegateduty", "wgdc", "wgduty", "wastegateposition",
                              "wgposition", "wastegatedutycycle"]),
        (LogChannel.fuelTrim.id, ["fueltrim", "stft", "ltft", "shorttermfueltrim",
                              "longtermfueltrim", "trim", "fueladaptation", "fueladapt"]),
        (LogChannel.iat.id, ["iat", "intakeairtemp", "intaketemp", "chargeairtemp", "airtemp",
                              "act", "intaketemperature", "intakeairtemperature"]),
        (LogChannel.coolant.id, ["coolant", "coolanttemp", "ect", "watertemp", "enginetemp",
                              "coolanttemperature"]),
        (LogChannel.torque.id, ["torque", "enginetorque", "torqueactual", "actualtorque"]),
    ]

    private static let afrAliases: Set<String> = [
        "afr", "airfuelratio", "afractual", "widebandafr", "wideband", "afr1", "afraverage",
    ]

    private static let timeAliases: Set<String> = [
        "time", "timestamp", "seconds", "secs", "t", "sampletime", "logtime", "elapsed",
        "elapsedtime", "timesec", "times", "timems", "sessiontime",
    ]

    private static func isTimeColumn(_ name: String) -> Bool {
        timeAliases.contains(normalize(name))
    }

    private static func timeDivisor(forUnit unit: String) -> Double {
        switch normalize(unit) {
        case "ms", "millisecond", "milliseconds", "msec": return 1000
        case "us", "µs", "microsecond", "microseconds", "usec": return 1_000_000
        default: return 1
        }
    }

    // MARK: Header + value parsing

    /// Split "Boost Pressure (psi)" / "IAT [C]" into (name, unit); no parens → unit "".
    static func parseHeaderCell(_ cell: String) -> (name: String, unit: String) {
        let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = trimmed.lastIndex(where: { $0 == "(" || $0 == "[" }) else {
            return (trimmed, "")
        }
        let closer: Character = trimmed[open] == "(" ? ")" : "]"
        guard trimmed.last == closer, open < trimmed.index(before: trimmed.endIndex) else {
            return (trimmed, "")
        }
        let name = String(trimmed[..<open]).trimmingCharacters(in: .whitespaces)
        let unit = String(trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)])
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? (trimmed, "") : (name, unit)
    }

    static func number(_ field: String) -> Double? {
        let trimmed = field.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        return Double(trimmed)
    }

    private static func normalize(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    private static func slug(_ s: String) -> String {
        var out = ""
        var lastUnderscore = false
        for scalar in s.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastUnderscore = false
            } else if !lastUnderscore {
                out.append("_")
                lastUnderscore = true
            }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    // MARK: CSV tokenizer

    /// Parse CSV text into rows of fields. Handles quoted fields (with embedded commas, newlines
    /// and `""` escapes), CRLF / LF / CR line endings, a leading UTF-8 BOM, and an auto-detected
    /// delimiter (comma, semicolon, or tab).
    static func parseCSV(_ text: String) -> [[String]] {
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        let delimiter = detectDelimiter(scalars)

        var rows: [[String]] = []
        var field = String.UnicodeScalarView()
        var row: [String] = []
        var inQuotes = false
        var i = 0

        func endField() { row.append(String(field)); field = String.UnicodeScalarView() }
        func endRow() { endField(); rows.append(row); row = [] }

        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < scalars.count && scalars[i + 1] == "\"" {
                        field.append("\""); i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case delimiter: endField()
                case "\n": endRow()
                case "\r":
                    endRow()
                    if i + 1 < scalars.count && scalars[i + 1] == "\n" { i += 1 }
                default: field.append(c)
                }
            }
            i += 1
        }
        // Flush trailing field/row unless the text ended exactly on a row terminator.
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    private static func detectDelimiter(_ scalars: [Unicode.Scalar]) -> Unicode.Scalar {
        // Count candidates on the first line only (outside quotes).
        var counts: [Unicode.Scalar: Int] = [",": 0, ";": 0, "\t": 0]
        var inQuotes = false
        for c in scalars {
            if c == "\"" { inQuotes.toggle(); continue }
            if inQuotes { continue }
            if c == "\n" || c == "\r" { break }
            if counts[c] != nil { counts[c]! += 1 }
        }
        return counts.max { $0.value < $1.value }?.key ?? ","
    }

    private func isBlank(_ row: [String]) -> Bool {
        row.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
