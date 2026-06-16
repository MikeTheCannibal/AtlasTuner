# Reading the ROM from the vehicle

The **Read from Vehicle** flow (car icon in the workspace toolbar) downloads a 1:1 copy of the
calibration running on the car so you can verify and compare it. It is **read-only** — Atlas Tune
never writes to the ECU.

## What it does

1. Connects over the ENET cable via the shared `DoIPClient` (DoIP routing activation, extended
   session).
2. If a `SecurityAccessProvider` is supplied, performs a seed/key unlock.
3. Reads the calibration region in chunks with **ReadMemoryByAddress** (`0x23`), assembling a
   `BINImage` with live progress (`VehicleROMReader` → `ROMReadPlan` / `ROMAssembler`).
4. Identifies the downloaded image and lets you:
   - **Verify vs working file** — exact match check (CRC) plus a per-table difference summary,
     answering "does my tune match what's on the car?"
   - **Open as New Project** — edit/inspect the downloaded copy directly.
   - **Keep as Reference for Compare** — store it in the revision tree to diff against your edits or
     a stock file (via the Difference Engine).

## The two blockers (be honest about these)

- **Security access.** Reading protected flash on the MG1 requires a UDS security unlock whose S58
  seed→key algorithm is proprietary and is **not** bundled. Conform a type to
  `SecurityAccessProvider` (with a routine you are authorised to use for your own vehicle) and pass
  it to `VehicleROMReader`. Without it, the ECU replies "security access denied" (NRC 0x33) and the
  read surfaces a clear error. Atlas Tune does not bypass ECU security.
- **Flash base / layout.** `ROMLayout.s58(flashBase:)` defaults to `0x80000000` as a structural
  placeholder so the read aligns 1:1 with the BIN/XDF file offsets. Confirm the actual flash base
  and region size for the MG1 software build before trusting the dump (the read field "Flash base"
  lets you set it).

## Comparing without a full download

Verification (A) and compare-vs-stock (B) also work entirely offline once you have files: import a
stock BIN and your tune, open one, and use the revision **Compare** to diff them — no vehicle
connection needed. The vehicle read adds the third reference point: what is actually flashed now.
