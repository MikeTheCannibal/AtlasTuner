# Datalogging

Atlas Tune's logging layer is modular: every source conforms to `DatalogSource`
(`AsyncStream<LogSample>`), so the live tiles, active-cell heat map, raw table and CSV export all
work identically regardless of where the data comes from.

## Sources

| Source | What it is | Status |
|--------|------------|--------|
| **Demo** (`PreviewSource`) | A simulated sine/cosine signal. Not vehicle data — it exists to exercise the UI and active-cell tracker without hardware. | Works everywhere |
| **Import Log** (`CSVImporter` + `ReplayDatalogSource`) | Load a recorded CSV (incl. MHD / MHD+ exports). The raw table and heat map populate immediately; **Replay** animates it through the pipeline. | Works everywhere |
| **Live (ENET)** (`ENETDatalogSource`) | Real-time capture from the car over a BMW ENET cable. | Transport real; **needs verified S58 DIDs + on-vehicle test** |

## CSV import (MHD+ logs)

`CSVImporter` is tolerant of real logs:

- Strips a UTF-8 BOM and blank lines.
- Finds the **time** column by name (`time`/`timestamp`/`elapsed`/`zeit`), else uses the first
  column. Accepts seconds or `HH:MM:SS.fff` clock time (converted to elapsed seconds).
- Maps headers back to the canonical S58 channels by **alias** (e.g. `RPM`, `Engine Speed`,
  `Drehzahl` → RPM; `Calculated Load` → Load), so the active-cell tracker keeps working.
- Keeps unmapped columns as their own channels, and de-duplicates repeated concepts
  (`Boost` vs `Boost Target`) into distinct channels.

If your MHD+ export doesn't map cleanly, send a header row — the alias table is plain data and easy
to extend.

## Live ENET capture (DoIP / UDS)

BMW F/G-series ECUs are reached over an ENET (Ethernet) cable using **DoIP** (ISO 13400), which
tunnels **UDS** (ISO 14229) diagnostic services. `ENETDatalogSource`:

1. Opens TCP to the gateway (default port **13400**).
2. Sends a **routing activation** request and waits for success.
3. Optionally enters an **extended diagnostic session** (`0x10 0x03`).
4. Polls the configured **data identifiers** each cycle via `ReadDataByIdentifier` (`0x22`),
   handling `0x78` "response pending", and decodes each response into a `LogSample`.

The protocol framing (`DoIP`, `UDS`) lives in the engine and is unit-tested. The byte transport
uses `Network.framework` in the app layer.

### What's required to read real channels

- **A verified S58 DID map.** `ENETChannelMap.s58Placeholder` has the right *shape* but illustrative
  identifiers/addresses — BMW's live-logging DIDs are not published. Replace them with verified
  values (and confirm the tester `0x0E00` / ECU address) in `ENETChannelMap`.
- **Network reachability.** The device must be on the vehicle's network (an ENET cable to a
  USB-Ethernet adapter, or the gateway's Wi-Fi). iOS will prompt for **local-network access**; the
  Xcode build declares `NSLocalNetworkUsageDescription`. In Swift Playgrounds, local-network
  connections may be restricted — run the Xcode build for on-vehicle testing.
- **Safety.** This is read-only logging (ReadDataByIdentifier). Atlas Tune never writes to the ECU.
