# Roadmap & Status

## Complete in this repository

**Engine (`AtlasTuneCore`) — implemented and unit-tested**

- [x] Data model: `DataType`, `Scaling`, `ByteOrder`, categories, ROM identity
- [x] Data-driven definition engine (`TableDefinition`, `AxisDefinition`, `DefinitionPackage`)
- [x] S58 (G87 M2) Phase 1 definition package across Fuel / Ignition / Boost / Torque / Safety
- [x] `BINImage` — endianness-aware, bounds-checked, copy-on-write read/write
- [x] Automatic ROM identification (`ROMIdentifier`, `DefinitionCatalog`)
- [x] `TableAccessor` — read/write engineering values with scaling, clamping, rounding
- [x] Edit engine — set/add/sub/mul/div/percent, interpolate, smooth, flatten, paste
- [x] Unlimited undo/redo (`UndoStack`)
- [x] Revision tree + structured difference engine
- [x] Logging model, CSV export, `DatalogSource` abstraction, replay source
- [x] **Active-cell tracker** (flagship): nearest-cell mapping, hit frequency, recency, heat map
- [x] Instant ranked table search
- [x] Export validation + checksum strategy abstraction
- [x] Export: BIN, revision package, metadata report
- [x] `CalibrationProject` facade
- [x] XCTest suite covering the above

**App layer (`App/AtlasTune`) — implemented against the engine**

- [x] `@main` app with SwiftData + CloudKit container
- [x] SwiftData persistence models + engine bridge (`ProjectStore`)
- [x] Final-Cut-style workspace (`NavigationSplitView`): navigator · editor · inspector
- [x] Category navigator with instant search
- [x] Spreadsheet editor with magnitude colouring + heat-map overlay
- [x] 2D graph view (Swift Charts)
- [x] Metal 3D surface renderer + shader, orbit/zoom/pan gestures, 120 FPS target
- [x] Live datalog panel + active-cell readout
- [x] Revision list + compare-to-working diff
- [x] Export menu (BIN / revision package / report) + validation
- [x] Apple Pencil markup overlay (PencilKit)
- [x] XcodeGen `project.yml`, Info.plist, entitlements

## Reconciled against a real image

- [x] **ROM identification** — verified against a real G87 M2 image: 8 MB MG1CS049 dump reporting
      `DME8.6.S_S58_G87`, calibration `CB_011_253.23.0_1.2.0`. The package now identifies by image
      size + two byte signatures (`#DME_86T0#CX#BTL#MDG1_I35UP` at 0x5FE1E, `DME8.6.S_S58_G87` at
      0x7FFE51) and extracts the calibration banner at 0x29000. Covered by `S58IdentificationTests`.
      (The proprietary BIN itself is not committed — it embeds a VIN.)

## Pending real-world reconciliation

- [ ] **Verified S58 map (table value) addresses** — the table value offsets in `Definitions/S58`
      remain structural placeholders. Reconcile against a known-good S58 map. (Data only; no code
      change.)
- [ ] **Real checksum scheme** — `CRC32ChecksumStrategy` is a placeholder; slot in the documented
      MG1 block polynomial/seed via the definition package.
- [ ] **Datalog hardware source** — implement a concrete `DatalogSource` for the chosen transport
      (BLE / Wi-Fi bridge / OBD). The `ReplayDatalogSource` and `PreviewSource` already exercise the
      pipeline.

## Future modules (per spec)

- [ ] **Atlas AI** — knock/lean/boost-deviation trend detection and region suggestions. Advisory
      only; never auto-edits. Will consume `LogSession` + `ActiveCellTracker` output.
- [ ] Surface comparison mode (stock vs modified) and colour-coded difference surface — the diff
      data already exists via `DifferenceEngine`; needs a second mesh + shader path.
- [ ] Multi-log overlay and per-region time-spent analytics.
