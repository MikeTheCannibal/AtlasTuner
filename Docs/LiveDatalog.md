# Live Datalogging (DoIP over Ethernet)

Atlas Tune can stream live vehicle data over **DoIP** (Diagnostics over IP, ISO 13400) — the
transport BMW G-series (incl. the G87 M2 / S58) use — so the flagship heat map, active-cell
tracker and Atlas AI all run in real time on the car, not just on imported logs.

## Physical connection

The OBD-II port carries automotive Ethernet (100BASE-T1) on dedicated pins, not the classic CAN
pins. To reach a Mac/iPad you need a **100BASE-T1 ↔ 100BASE-TX media converter** that breaks the
OBD Ethernet out to a standard **RJ45**, plus the connector's activation line energised:

```
Vehicle OBD-II ──(100BASE-T1)── media converter ──(RJ45 / 100BASE-TX)── Mac/iPad Ethernet
```

The vehicle then appears on a link-local network (typically `169.254.x.x`). DoIP diagnostics run on
**TCP port 13400**.

## How the stack works

The pipeline is layered so the protocol logic is pure and testable and the socket is swappable:

| Layer | Type | Role |
|-------|------|------|
| Framing | `DoIPMessage` | ISO 13400 generic header + payloads (routing activation, diagnostic message). |
| Service | `UDSService` | ISO 14229 `ReadDataByIdentifier` requests + response/NRC parsing. |
| Channel map | `UDSDataIdentifier` / `LiveChannelSet` | Data-driven: which DIDs to poll and how to scale each into a `LogChannel`. |
| Decode | `LiveChannelDecoder` | Raw response bytes → engineering value (type, byte order, scaling). |
| Transport | `ByteTransport` | The swappable byte pipe. `TCPByteTransport` (Network.framework) is the wired path; a BLE adapter is the same seam. |
| Orchestration | `DoIPClient` | Routing activation, then polls DIDs and handles `0x78` response-pending. |
| Source | `LiveDatalogSource` | A `DatalogSource` that yields `LogSample`s into the existing pipeline. |

Because `LiveDatalogSource` conforms to the same `DatalogSource` protocol as the CSV/replay path,
everything downstream (heat map, `ActiveCellTracker`, `AtlasAI`, `CorrectionEngine`) is identical
whether the data came from a file or the car.

## In the app

Datalog panel → enter the vehicle's DoIP IP → **Connect**. Samples stream in; **Stop** ends the
session.

## Status and caveats

- **The transport, framing, UDS and streaming are implemented and tested** — unit tests cover the
  codecs and an end-to-end loopback test drives `LiveDatalogSource` against an in-memory DoIP ECU;
  the real `TCPByteTransport` was verified against a live loopback TCP DoIP server.
- **The S58 DID map (`LiveChannelSet.s58Placeholder`) is provisional.** The data identifiers and
  scalings are conventional/OBD-style placeholders and must be reconciled against a real G87
  (an ODX/A2L or logging the car and comparing to MHD) before the readings are trustworthy. This
  is a *data* change — no code edits — matching the definition-engine philosophy.
- **Discovery is out of scope here.** Construct the session with the DoIP entity's IP and logical
  address directly. The UDP vehicle-identification broadcast/announcement and DoIP security access
  (for protected data) are future additions.
- **BLE** wireless adapters plug into the same `ByteTransport` seam; a concrete CoreBluetooth
  transport is the next transport to add.
