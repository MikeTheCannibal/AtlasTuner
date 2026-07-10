import Foundation
import AtlasTuneCore

// Command-line companion for reconciling the real S58 DID map from the car. Three subcommands:
//
//   scan <host> [loHex hiHex]                 discover responding DIDs over DoIP  → did_scan.csv
//   capture <host> --dids H,H,.. --seconds N  record raw DID values over a drive → did_capture.csv
//   reconcile <capture.csv> <mhd.csv>         correlate against a labelled MHD log → live_channels.json
//
// `scan`/`capture` need the car (OBD→100BASE-T1→RJ45, DoIP on TCP 13400) and are read-only —
// they issue only ReadDataByIdentifier (0x22) and never write to the ECU. `reconcile` is offline.

enum AtlasDIDTool {
    static func run() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else { return usage() }
        do {
            switch command {
            case "scan": try await scan(Array(args.dropFirst()))
            case "capture": try await capture(Array(args.dropFirst()))
            case "reconcile": try reconcile(Array(args.dropFirst()))
            default: usage()
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }

    // MARK: scan

    static func scan(_ args: [String]) async throws {
        guard let host = args.first else { return usage() }
        let lo = args.count > 1 ? UInt16(args[1].replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0xF400 : 0xF400
        let hi = args.count > 2 ? UInt16(args[2].replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0xF4FF : 0xF4FF
        print("Scanning \(host) DIDs 0x\(String(lo, radix: 16))…0x\(String(hi, radix: 16)) (read-only)…")
        let scanner = DIDScanner(client: DoIPClient(transport: TCPByteTransport(host: host)))
        let probes = try await scanner.scan(range: lo...hi) { did, found in
            if did % 0x10 == 0 { FileHandle.standardError.write(Data("  …0x\(String(did, radix: 16)) (\(found) found)\r".utf8)) }
        }
        var csv = "did,byteLength,sampleHex\n"
        for p in probes {
            csv += String(format: "0x%04X,%d,%@\n", p.did, p.byteLength, p.sample.map { String(format: "%02X", $0) }.joined())
        }
        try csv.write(toFile: "did_scan.csv", atomically: true, encoding: .utf8)
        print("\n\(probes.count) responders → did_scan.csv")
    }

    // MARK: capture

    static func capture(_ args: [String]) async throws {
        guard let host = args.first else { return usage() }
        let dids = value(args, "--dids").map { $0.split(separator: ",").compactMap { UInt16($0.replacingOccurrences(of: "0x", with: ""), radix: 16) } } ?? []
        let seconds = value(args, "--seconds").flatMap(Double.init) ?? 60
        let rate = value(args, "--rate").flatMap(Double.init) ?? 20
        guard !dids.isEmpty else { return usage() }
        print("Capturing \(dids.count) DIDs for \(Int(seconds))s at \(Int(rate)) Hz…")
        let capture = DIDCapture(client: DoIPClient(transport: TCPByteTransport(host: host)))
        let series = try await capture.record(dids: dids, duration: seconds, pollRate: rate) { t in
            FileHandle.standardError.write(Data(String(format: "  …%.0fs\r", t).utf8))
        }
        try DIDCaptureFile.csv(series).write(toFile: "did_capture.csv", atomically: true, encoding: .utf8)
        print("\n\(series.count) DID series → did_capture.csv")
    }

    // MARK: reconcile (offline)

    static func reconcile(_ args: [String]) throws {
        guard args.count >= 2 else { return usage() }
        let capture = try DIDCaptureFile.parse(String(contentsOfFile: args[0], encoding: .utf8))
        let reference = try CSVLogImporter().session(from: Data(contentsOf: URL(fileURLWithPath: args[1])),
                                                     name: "reference")
        let candidates = DIDReconciler().reconcile(capture: capture, reference: reference)

        print("Reconciled \(candidates.count) channel(s) from \(capture.count) DIDs vs \(reference.channels.count) reference channels:\n")
        for c in candidates {
            let mark = c.isConfident ? "✓" : "?"
            print(String(format: "  %@ %-8@ DID 0x%04X  raw×%.5g%+.4g → %@  (r=%.3f, runner-up %.3f, lag %+.2fs)",
                         mark, c.channel.id, c.did, c.scaling.factor, c.scaling.offset, c.channel.unit,
                         c.correlation, c.runnerUpCorrelation, c.appliedLag))
        }
        let set = LiveChannelSet(identifiers: candidates.filter(\.isConfident).map(\.identifier))
        let json = try JSONEncoder.pretty.encode(set)
        try json.write(to: URL(fileURLWithPath: "live_channels.json"))
        print("\n\(set.identifiers.count) confident channel(s) → live_channels.json")
    }

    // MARK: helpers

    static func value(_ args: [String], _ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func usage() {
        print("""
        AtlasDIDTool — reconcile the S58 live DID map (read-only over DoIP)

          scan <host> [loHex hiHex]                 discover responding DIDs        → did_scan.csv
          capture <host> --dids H,H,… --seconds N [--rate R]  record a drive        → did_capture.csv
          reconcile <capture.csv> <mhd.csv>         correlate vs a labelled MHD log → live_channels.json
        """)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }
}

await AtlasDIDTool.run()
