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

## Adding a ROM family

Adding B58/S63/etc. in a later phase is a **data** task:

1. Author a new `DefinitionPackage` (its own file under `Definitions/<family>/`).
2. Register it in `DefinitionCatalog`.

No engine or UI code changes — the navigator, editor, search, diff and export are all driven by the
package data.
