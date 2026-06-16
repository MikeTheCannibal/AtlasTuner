# Atlas Tune

Professional ECU calibration editing and datalog analysis for iPadOS — *"Final Cut Pro for ECU
calibration."*

Atlas Tune is **not** a flashing application. It complements MHD, bootmod3 and other flashing
platforms by providing a modern, touch-first environment to edit calibrations, analyse logs, and
manage revisions. The typical workflow is: read with an existing tool → **import → edit → analyse
→ revise → export** → flash with MHD.

> **Phase 1 scope:** the 2025 BMW M2 (G87) / **S58** engine, one ROM family done well. No B58,
> S63 or other platforms yet — the architecture is data-driven so adding families later is a data
> task, not a code rewrite.

## Project layout

```
AtlasTuner/
├── Package.swift              # SwiftPM manifest for the engine + tests
├── project.yml               # XcodeGen spec for the iPadOS app target
├── Sources/AtlasTuneCore/     # Foundation-only engine (no UIKit/SwiftUI) — fully unit-tested
│   ├── Models/                #   value types: tables, scaling, data types, ROM identity
│   ├── Definitions/           #   data-driven definition engine + S58 package
│   ├── BIN/                   #   image read/write, ROM identification, table accessor
│   ├── Editing/               #   edit operations, interpolation, smoothing, undo
│   ├── Revisions/             #   revision tree + difference engine
│   ├── Logging/               #   channels, sessions, CSV, active-cell tracker
│   ├── Search/                #   instant table search index
│   ├── Safety/                #   export + checksum validation
│   ├── Export/                #   BIN / revision package / metadata report
│   └── Project/               #   CalibrationProject aggregate (the engine facade)
├── App/AtlasTune/             # SwiftUI + Metal + SwiftData app layer
│   ├── App/                   #   @main entry, ModelContainer (CloudKit)
│   ├── Persistence/           #   SwiftData models + engine bridge
│   ├── Features/              #   Workspace, TableEditor, Surface3D, Datalog, Revisions, …
│   └── Resources/             #   Info.plist, entitlements, Metal shaders
├── Tests/AtlasTuneCoreTests/  # XCTest suite for the engine
└── Docs/                      # Architecture, definition format, roadmap
```

## Why the split?

The **engine** (`AtlasTuneCore`) is pure Swift / Foundation: no Apple-UI dependencies, every
operation pure and `Sendable`. That makes it testable on its own and keeps all the hard logic
(byte layout, scaling, diffing, active-cell math) independent of the UI. The **app layer** is a
thin SwiftUI / Metal / SwiftData shell that drives the engine.

## Building

The engine builds and tests with SwiftPM:

```bash
swift test            # runs the AtlasTuneCore test suite
```

The iPadOS app is generated with [XcodeGen](https://github.com/yonsm/XcodeGen) and opened in Xcode
on macOS (the app target requires the iOS SDK, Metal and SwiftData):

```bash
xcodegen generate
open AtlasTune.xcodeproj
```

Target device: 2025 iPad Pro (M5), Apple Pencil Pro. Performance goals — open under 1s, 120 FPS
UI and surface, 100 Hz logging — are documented in `Docs/Architecture.md`.

## Swift Playgrounds

A ready-to-open Swift Playgrounds App project is provided at **`AtlasTune.swiftpm/`** — open it in
Swift Playgrounds (iPad or Mac) or Xcode 15+. It bundles the engine and app as two targets plus the
S58 JSON definitions, and runs without a developer account: SwiftData falls back from CloudKit to a
local/in-memory store, and the Metal surface shader compiles from source at runtime.

Regenerate it from the canonical sources with:

```bash
Tools/make_swiftpm.sh        # writes AtlasTune.swiftpm/ and AtlasTune.swiftpm.zip
```

## Status

This repository establishes the full architecture and a working, tested engine. UI feature views
are implemented against the engine and ready to build in Xcode. See `Docs/Roadmap.md` for what is
complete versus pending hardware / real-map work.

### Definitions

The Phase 1 S58 definitions (1370 tables, real file-offset addresses) are imported from the MHD+
XDF for this exact image via `Tools/xdf_to_definition.py` and bundled as
`Sources/AtlasTuneCore/Resources/s58_mg1cs049.json`, loaded automatically by
`DefinitionCatalog.phase1`. The compact `S58DefinitionPackage` remains a programmatic fallback. See
`Docs/DefinitionEngine.md` for the conversion details.
