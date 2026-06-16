# Atlas Tune — Architecture

## Layering

Atlas Tune is split into a pure engine and a UI shell:

```
┌──────────────────────────────────────────────────────────┐
│ App layer (App/AtlasTune)                                  │
│  SwiftUI views · Metal renderer · SwiftData · CloudKit     │
│  @Observable view models (MainActor)                       │
└───────────────▲────────────────────────────────────────────┘
                │ drives (value types in / out)
┌───────────────┴────────────────────────────────────────────┐
│ Engine (Sources/AtlasTuneCore) — Foundation only, Sendable  │
│  Definition engine · BIN I/O · Edit ops · Revisions/Diff    │
│  Logging + ActiveCellTracker · Search · Safety · Export     │
└─────────────────────────────────────────────────────────────┘
```

The engine has **no** dependency on UIKit, SwiftUI, Metal or SwiftData. Everything it exposes is a
value type (`struct`/`enum`) and `Sendable`, so it can run on a background actor and is trivially
unit-testable without a simulator.

## Key engine types

| Type | Responsibility |
|------|----------------|
| `DataType`, `Scaling`, `ByteOrder` | Raw byte encoding ↔ engineering value. |
| `TableDefinition`, `AxisDefinition` | Data-driven description of one table (no hard-coded UI). |
| `DefinitionPackage`, `DefinitionCatalog` | A ROM family's full table set + identification rules. |
| `BINImage` | Endianness-aware, bounds-checked, copy-on-write image. |
| `ROMIdentifier` | Auto-matches an image to a package (no manual XDF loading). |
| `TableAccessor` | Reads/writes a `CalibrationTable` of engineering values. |
| `EditEngine`, `Interpolation`, `Smoothing` | Pure edit operations over a `CellRegion`. |
| `UndoStack` | Generic, unlimited snapshot undo/redo. |
| `RevisionTree`, `DifferenceEngine` | Branching history + structured diffs. |
| `ActiveCellTracker` | Flagship: maps live operating points to cells, builds the heat map. |
| `TableSearchIndex` | Instant ranked search. |
| `ExportValidator`, `ChecksumStrategy` | Pre-export safety. |
| `CalibrationProject` | The facade that ties it all together for one open calibration. |

## Data flow: importing and editing

1. **Import** — `WorkspaceModel.importImage(_:)` hands raw bytes to a detached task.
2. **Identify** — `CalibrationProject.open` uses `DefinitionCatalog` → `ROMIdentifier` to pick a
   `DefinitionPackage` and produce a `ROMIdentity`. The initial image is captured as a "Stock"
   revision (automatic backup).
3. **Open table** — `TableAccessor.read` decodes bytes → `CalibrationTable` (engineering values +
   resolved axes).
4. **Edit** — `EditEngine.apply` produces a new `CalibrationTable`; `TableAccessor.write` writes it
   back to a copy of the image; the result is committed to the `UndoStack`.
5. **Revise** — `saveRevision` snapshots the working image into the `RevisionTree`.
6. **Export** — `CalibrationExporter` emits a BIN (optionally checksum-corrected), a revision
   package, or a metadata report.

## Concurrency

- Engine work is synchronous and pure; expensive calls (identification, full-image diff) are
  dispatched off the main actor by the view models.
- View models are `@MainActor @Observable` classes — the only mutable, observable state.
- `DatalogSource` exposes samples as an `AsyncStream`, consumed by `DatalogViewModel`.

## Performance posture (iPad Pro M5 targets)

- **Open < 1s / definitions < 250 ms** — definitions are in-memory Swift values; no parsing of XDF
  at runtime. `BINImage` is copy-on-write so snapshots are O(1) until divergence.
- **120 FPS surface** — `SurfaceMesh` builds an indexed triangle mesh once per table change;
  `SurfaceRenderer` reuses buffers and only updates small uniforms per frame; `MTKView` is set to
  `preferredFramesPerSecond = 120`.
- **100 Hz logging** — sample ingestion is O(1) per sample; `ActiveCellTracker.record` is a nearest
  -breakpoint scan over small axes.
- **Memory** — values are stored as compact arrays; undo snapshots share storage via COW.

## App layer notes

- `NavigationSplitView` provides the Final-Cut-style navigator · editor · inspector layout and
  adapts to Stage Manager / external displays automatically.
- SwiftData models (`StoredProject`, `StoredRevision`, `StoredLogSession`) persist the library and
  sync via CloudKit; `ProjectStore` bridges them to engine value types.
- Apple Pencil markup is a `PKCanvasView` overlay (`PencilAnnotationView`) with `.pencilOnly`
  drawing so finger gestures stay free for pan/zoom.
