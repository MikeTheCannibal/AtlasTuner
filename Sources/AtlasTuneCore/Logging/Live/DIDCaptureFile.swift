import Foundation

/// Portable CSV serialisation of a raw DID capture: a `time` column followed by one column per DID
/// (header `0xF40C` etc., value = the raw big-endian integer that cycle). Rows share the cycle
/// timestamp. This is the artefact a capture drive produces on the car and hands to the reconciler.
public enum DIDCaptureFile {
    /// Encode captures to CSV. All series are assumed to share cycle timestamps (as `DIDCapture`
    /// produces); the union of timestamps is used and missing cells left blank.
    public static func csv(_ captures: [CapturedDID]) -> String {
        let dids = captures.map(\.did)
        // Union of all timestamps, in order.
        var times: [TimeInterval] = []
        var seen = Set<String>()
        for capture in captures {
            for sample in capture.samples where seen.insert(String(format: "%.4f", sample.time)).inserted {
                times.append(sample.time)
            }
        }
        times.sort()

        // Per-DID lookup by rounded time key.
        let lookup: [UInt16: [String: Double]] = Dictionary(uniqueKeysWithValues: captures.map { capture in
            (capture.did, Dictionary(capture.samples.map { (String(format: "%.4f", $0.time), $0.raw) },
                                     uniquingKeysWith: { a, _ in a }))
        })

        var lines = ["time," + dids.map { String(format: "0x%04X", $0) }.joined(separator: ",")]
        for time in times {
            let key = String(format: "%.4f", time)
            var row = [String(format: "%.4f", time)]
            for did in dids {
                if let v = lookup[did]?[key] { row.append(String(format: "%g", v)) } else { row.append("") }
            }
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    public static func data(_ captures: [CapturedDID]) -> Data { Data(csv(captures).utf8) }

    public enum ParseError: Error, Equatable { case noHeader, noDIDColumns }

    /// Parse a capture CSV back into per-DID series. DID columns are recognised by a `0x` header.
    public static func parse(_ text: String) throws -> [CapturedDID] {
        let rows = text.split(whereSeparator: \.isNewline).map {
            $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        }
        guard let header = rows.first else { throw ParseError.noHeader }
        let didColumns: [(index: Int, did: UInt16)] = header.enumerated().compactMap { i, name in
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("0x"), let did = UInt16(trimmed.dropFirst(2), radix: 16) else { return nil }
            return (i, did)
        }
        guard !didColumns.isEmpty else { throw ParseError.noDIDColumns }

        var series: [UInt16: [TimedRaw]] = Dictionary(uniqueKeysWithValues: didColumns.map { ($0.did, []) })
        for row in rows.dropFirst() {
            guard let time = row.first.flatMap({ Double($0) }) else { continue }
            for column in didColumns where column.index < row.count {
                let cell = row[column.index].trimmingCharacters(in: .whitespaces)
                guard let raw = Double(cell) else { continue }
                series[column.did]?.append(TimedRaw(time: time, raw: raw))
            }
        }
        return didColumns.compactMap { column in
            let samples = series[column.did] ?? []
            guard !samples.isEmpty else { return nil }
            let width = samples.contains { $0.raw > 255 } ? (samples.contains { $0.raw > 65535 } ? 4 : 2) : 1
            return CapturedDID(did: column.did, byteLength: width, samples: samples)
        }
    }
}
