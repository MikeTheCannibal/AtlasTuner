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
4. Each cycle, reads every mapped signal's RAM address via **ReadMemoryByAddress** (`0x23`),
   handling `0x78` "response pending", and decodes the bytes into a `LogSample`.

The protocol framing (`DoIP`, `UDS`) lives in the engine and is unit-tested. The byte transport
uses `Network.framework` in the app layer.

### Where the channel map comes from

`ENETChannelMap.s58FromA2L` is built from the vehicle **A2L** `MEASUREMENT` objects — the
authoritative source for loggable signals:

- **Address** = the measurement's `ECU_ADDRESS` (RAM, e.g. `0x500020E6`).
- **Data type** = the A2L type (`SWORD`→int16, `UWORD`→uint16, `UBYTE`→uint8…).
- **Scaling factor** = the `COMPU_METHOD` ratio `f/b` (e.g. relative charge = `3/128 = 0.0234375`,
  which matches its `q0p0234` name; coolant `1/100`; intake temp `1/10`).
- **Byte order** = little-endian (A2L `BYTE_ORDER MSB_LAST`, consistent with TriCore RAM).

Channels currently mapped: RPM (`Epm_nEng`), load (`AirMod_ratChrgAirCyl`), coolant (`Tmot`),
intake air temp (`Tans`), total timing retard (`Dzw_tot_kr`), oil temp (`Toel_wm`), vehicle speed
(`V`), gear (`Gangi`), ambient pressure (`Pumg`), boost deviation (`Pld_diff`), knock intensity
(`IKCtl_facKnkInten_u8`), torque-limit factor (`BMWtqe_fac_EngTqLimd`).

### Caveats before trusting live values

- **Software variant.** The source A2L is `F4C2L8R6B` (EPK `5c64020_135_006`); the imported BIN is
  `F4C2L8Y8B` / CB_011. RAM addresses are tied to the software build — confirm them against the
  vehicle (or obtain the matching A2L). Lambda and absolute boost/manifold pressure are **not** in
  this A2L's measurement subset.
- **Network reachability.** The device must be on the vehicle's network (ENET cable to a
  USB-Ethernet adapter, or the gateway's Wi-Fi). iOS prompts for **local-network access**; the
  Xcode build declares `NSLocalNetworkUsageDescription`. Swift Playgrounds may restrict local-network
  connections — run the Xcode build on-vehicle.
- **Safety.** Read-only logging (ReadMemoryByAddress). Atlas Tune never writes to the ECU.

### Extending the map

To add channels, copy more `MEASUREMENT` entries from the A2L: take `ECU_ADDRESS`, map the type,
and set the factor to the `COMPU_METHOD` `f/b`. `Tools/a2l_measurements.py` lists every measurement
with its address, type and decoded factor.
