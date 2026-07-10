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

## Reconciling the real S58 DID map (learning from the car)

The live source needs to know **which DID carries which channel and its scaling**. Rather than trust
the `s58Placeholder` guesses, Atlas Tune *learns* the map from data, using an MHD log as ground
truth. This runs **inside the app** — Datalog panel → **Reconcile DID Map…** — with no separate
tool or runtime. Scanning and capture are **read-only**: they issue only `ReadDataByIdentifier`
(0x22) and never write to the ECU.

### You don't need both loggers connected at once

MHD runs on your phone; the Mac connects over the DoIP cable, and they can't share the OBD port —
that's fine. Cross-correlation only needs the two logs to describe the **same events**, not the same
connection. Every log contains RPM, whose idle/rev/decel fingerprint is unmistakable, so two
*separate* drives are aligned afterwards by warping their timelines until the RPM traces line up;
once RPM aligns, every other channel aligns with it.

### Script *held steady-states*, not sweeps

Two separate drives can't reproduce identical transients but can reproduce **held operating points**:

> idle 30 s → hold 2000 rpm 10 s → 3000 rpm 10 s → 4000 rpm part-throttle 10 s →
> 4000 rpm near-WOT 10 s → decel → repeat once

Holds give high confidence on RPM/load/throttle/temps, good on boost, honest-but-lower on
lambda/knock. Discovery and the RPM/temps/throttle channels can be done **stationary**; only
load-dependent channels (boost, lambda, knock) need a drive or dyno.

### Procedure (all in-app)

Open the datalog panel and tap **Reconcile DID Map…**. The sheet walks three steps:

1. **Scan** — enter the vehicle's DoIP IP and scan; the app lists which DIDs the ECU answers and
   their widths (stationary, read-only).
2. **Capture** — record raw DID values over the scripted drive (Atlas only). Log the **same** script
   in MHD separately and export its CSV. (Captured earlier? **Import…** a saved capture instead.)
3. **Reconcile** — choose the MHD log and tap Reconcile.

The reconciler aligns the logs on RPM, finds the DID whose raw series best tracks each MHD channel,
fits the linear scaling by least squares, and reports Pearson *r* plus the runner-up margin. Channels
that are well-correlated **and** clearly separated from the runner-up are marked confident (`✓`).
**Apply** adopts the confident map for live logging this session; **Export JSON** saves it as a
`LiveChannelSet` to fold into the S58 definition. Review the `?` rows and confirm against a second
capture before trusting them.

**Honest limits:** this is a capture→analyze→verify loop, not interactive real-time probing; each DID
is treated as a single value (multi-field DIDs surface as low-confidence); some DIDs need an extended
session or security access to read.

## Status and caveats

- **The transport, framing, UDS and streaming are implemented and tested** — unit tests cover the
  codecs and an end-to-end loopback test drives `LiveDatalogSource` against an in-memory DoIP ECU;
  the real `TCPByteTransport` was verified against a live loopback TCP DoIP server.
- **The S58 DID map (`LiveChannelSet.s58Placeholder`) is provisional.** The data identifiers and
  scalings are conventional/OBD-style placeholders and must be reconciled against a real G87 before
  the readings are trustworthy — see *Reconciling the real S58 DID map* above for the in-app,
  read-only workflow that learns the map by correlating a car capture against an MHD log. This
  is a *data* change — no code edits — matching the definition-engine philosophy.
- **Discovery is out of scope here.** Construct the session with the DoIP entity's IP and logical
  address directly. The UDP vehicle-identification broadcast/announcement and DoIP security access
  (for protected data) are future additions.
- **BLE** wireless adapters plug into the same `ByteTransport` seam; a concrete CoreBluetooth
  transport is the next transport to add.
