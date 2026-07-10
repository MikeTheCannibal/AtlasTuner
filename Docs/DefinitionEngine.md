# The Definition Engine

Atlas Tune never asks the tuner to load an XDF, XML map, or address table. Instead it ships
**definition packages** — pure Swift data describing each ROM family — and identifies images
automatically.

## A definition package

```swift
DefinitionPackage(
    id: "bmw.s58.mg1cs003.phase1",
    family: "S58 / MG1CS003",
    calibrationVersion: "Phase 1",
    expectedImageSizes: [4 * 1024 * 1024],
    versionField: VersionField(address: 0x..., length: 24),   // optional banner
    signatures: [ ROMSignature(address: 0x..., pattern: [...]) ],
    tables: [ /* TableDefinition values */ ]
)
```

## A table definition

```swift
TableDefinition(
    id: "ign.base",
    name: "Base Timing",
    category: .ignition,
    subcategory: "Base Timing",
    address: 0x10000,
    dataType: .uint16,
    scaling: Scaling(factor: 0.1, offset: -10, decimals: 1),  // display = raw*0.1 - 10
    unit: "°",
    rows: 15, columns: 15,
    xAxis: S58Axes.rpm,        // columns
    yAxis: S58Axes.load,       // rows (omit for 1D)
    valueRange: -10...45       // validation + edit clamp
)
```

- **Scaling** is linear (`display = raw * factor + offset`) which covers the vast majority of MG1
  tables. The `ValueTransform` protocol leaves room for non-linear transforms without changing call
  sites.
- **Axes** are either `.stored` (breakpoints live in the BIN and are themselves calibratable) or
  `.fixed` (constant breakpoints baked into the definition).
- **Dimensionality** (`scalar`/`oneD`/`twoD`/`threeD`) is derived from `rows`, `columns` and whether
  a `yAxis` is present; the renderer uses it to pick a default view.

## Identification

`ROMIdentifier.identify(_:)` scores each package against an image:

1. If the package declares `expectedImageSizes`, the image size must match.
2. Confidence = fraction of `signatures` whose bytes match at their address.
3. The highest-confidence package wins; its `versionField` (if any) is read to report the exact
   calibration version.

This is the single automatic step that turns a blob of bytes into an editable calibration with the
correct table set.

## Importing definitions from an XDF

`Tools/xdf_to_definition.py` converts a TunerPro/MHD+ XDF into a JSON `DefinitionPackage` matching
the engine's Codable shape (including Swift's synthesized enum encoding for `AxisDefinition.Source`).
The Phase 1 package `Sources/AtlasTuneCore/Resources/s58_mg1cs049.json` (1370 tables) was generated
this way from the MHD+ XDF for the real G87 image and is loaded by `DefinitionCatalog.phase1` via
`Bundle.module`.

```bash
python3 Tools/xdf_to_definition.py input.xdf Sources/AtlasTuneCore/Resources/s58_mg1cs049.json
```

Mapping highlights: `mmedaddress` → file offset; element size + `mmedtypeflags` (0x01 signed,
0x10000 float) → `DataType`; MATH equation → linear `Scaling`; XDF category → one of the five
top-level categories with the original name kept as `subcategory`.

## Cross-variant name recovery

The MHD+-derived XDF that `Tools/xdf_to_definition.py` consumed leaves some tables unnamed —
these get a synthetic `"... (autogen)"` title. A related S58 variant's XDF (`F4C9L8R5B`,
same 8 MB layout and base offset) is fully authored with no autogen titles, so in principle its
table names can be borrowed wherever the two variants share a flash address.

In practice, address equality across variants is a **weak** signal on its own: of 13 candidate
matches checked, 3 named a completely different, semantically unrelated table at the same
address — a coincidental collision between the two builds' memory layouts, not the same
calibration. Only address matches whose meaning was independently confirmed by consistent
semantics on both sides were applied (6 tables, an oil-pressure breakpoint cluster at
`0x700e8a`–`0x701010`, `s58_mg1cs049.json` ids `xdf0000/0001/0003/0004/0006/0007`). Do **not**
bulk-apply address matches from another variant without checking each one's semantics — a wrong
label is worse than an honest `"(autogen)"`.

## Adding a ROM family

Adding B58/S63/etc. in a later phase is a **data** task:

1. Author a new `DefinitionPackage` (its own file under `Definitions/<family>/`).
2. Register it in `DefinitionCatalog`.

No engine or UI code changes — the navigator, editor, search, diff and export are all driven by the
package data.

## Checksum scheme

A package may carry the family's checksum block layout in an optional `checksumScheme` field
(`DefinitionPackage.checksumScheme`). When present, `ExportValidator` verifies the blocks
(stale checksums surface as warnings) and BIN export recomputes them automatically via
`SchemeChecksumStrategy`; when absent, exports are unmodified.

```json
"checksumScheme": {
  "blocks": [
    {
      "name": "Calibration block",
      "ranges": [
        {"start": 131072, "length": 393216},
        {"start": 524292, "length": 131068}
      ],
      "storedAt": 524288,
      "storedByteOrder": "littleEndian",
      "algorithm": {"preset": "crc32-bzip2"}
    }
  ]
}
```

`ranges` are fed to the CRC in order, so a block excludes its own stored checksum by splitting
around it. `algorithm` is either a preset (`crc32`, `crc32-bzip2`, `crc32-mpeg2`, `crc32-posix`,
`crc16-ccitt-false`, `crc16-arc`) or explicit Rocksoft parameters — `width`, `polynomial`,
`initialValue`, `xorOut` (numbers or `"0x…"` hex strings), `reflectInput`, `reflectOutput`.

To discover the real block layout for a family, run the scanner against a **known-good** image:

```bash
Tools/find_checksums.py stock.bin            # 64 KB boundaries
Tools/find_checksums.py stock.bin --align 0x1000
```

It brute-forces eight CRC-32 variants plus additive sums over every aligned boundary pair and
prints a ready-to-paste JSON snippet for each match.

**A single scan is not enough.** With tens of thousands of candidate ranges, ten algorithms and
millions of stored words, hundreds of coincidental 32-bit collisions are expected by chance — a
raw hit count near that noise floor means nothing real was found. (On the Phase 1 MG1CS049 image
a 64 KB scan returns ~67 hits, *below* the ~300 expected from chance and scattered across every
algorithm and both endiannesses: pure noise, no recoverable scheme.)

To separate real checksums from coincidence, compare **two known-good images of the same ROM but
with different data** (two stock reads from different cars, or a re-read):

```bash
Tools/find_checksums.py --compare carA.bin carB.bin
```

A real checksum validates at the same `(range, algorithm, stored offset, endianness)` in both
images even though its stored value differs; a coincidence would have to recur at those exact
coordinates in the second image (~2⁻³²), so the noise floor collapses. Only the intersection is
printed, ranked with the strongest evidence — candidates whose covered block data differs between
the two reads — first. Even then, sanity-check a candidate by editing a byte in range and
re-flashing on the bench before trusting it.
