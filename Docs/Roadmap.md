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

- [x] **Real table definitions** — 1370 tables imported from the MHD+ XDF for this exact image
      (`F4C2L8Y8B` / CB_011) via `Tools/xdf_to_definition.py`, emitted as the bundled JSON package
      `Sources/AtlasTuneCore/Resources/s58_mg1cs049.json` and loaded by `DefinitionCatalog.phase1`.
      Addresses are direct file offsets; XDF MATH equations are reduced to linear factor/offset.
      The compact programmatic `S58DefinitionPackage` remains as a fallback.

## Pending real-world reconciliation

- [ ] **A2L cross-reference** — the supplied A2L is a *different* variant (`F4C2L8R6B`) using
      TriCore virtual addresses (`0x807xxxxx`), so it was **not** merged (address base + variant
      mismatch with this image). It can later supply canonical OEM names / `COMPU_METHOD` scaling
      once a memory-map translation and variant match are in place.
- [ ] **Non-linear scaling** — XDF non-linear MATH equations are currently linearly approximated
      (none in the supplied file). Add a non-linear `ValueTransform` if a future map needs one.
- [ ] **Real checksum scheme** — the engine side is done: `SchemeChecksumStrategy` executes a
      data-driven `ChecksumScheme` (any Rocksoft CRC-16/32, multi-range blocks, per-block stored
      byte order) carried by the definition package, wired into `ExportValidator` and BIN export.
      Remaining: discover the MG1CS049 block layout from a known-good image with
      `Tools/find_checksums.py` and add it to `s58_mg1cs049.json` (see
      `Docs/DefinitionEngine.md` § Checksum scheme).
- [ ] **Datalog hardware source** — implement a concrete `DatalogSource` for the chosen transport
      (BLE / Wi-Fi bridge / OBD). The `ReplayDatalogSource` and `PreviewSource` already exercise the
      pipeline.

## Future modules (per spec)

- [ ] **Atlas AI** — knock/lean/boost-deviation trend detection and region suggestions. Advisory
      only; never auto-edits. Will consume `LogSession` + `ActiveCellTracker` output.
- [ ] Surface comparison mode (stock vs modified) and colour-coded difference surface — the diff
      data already exists via `DifferenceEngine`; needs a second mesh + shader path.
- [ ] Multi-log overlay and per-region time-spent analytics.
