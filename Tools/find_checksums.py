#!/usr/bin/env python3
"""Locate checksum-protected blocks in an ECU BIN by brute force.

Feed it a KNOWN-GOOD image (e.g. a stock read that the ECU accepts). It scans every pair of
aligned boundaries as a candidate block, computes eight CRC-32 variants plus additive sums over
each, and searches the image for a stored 32-bit word matching the result. Findings print with a
ready-to-paste `checksum` JSON snippet for the definition package
(Sources/AtlasTuneCore/Resources/*.json).

    Tools/find_checksums.py stock.bin
    Tools/find_checksums.py stock.bin --align 0x1000 --min-length 0x4000

All eight CRC-32 variants (reflected x init x xorOut) run at C speed: zlib.crc32 covers the
reflected ones, and the non-reflected ones reuse zlib on a bit-reversed copy of the image
(reversing bits of every byte turns an MSB-first CRC into an LSB-first one over the same
polynomial).

Caveats: results are candidates, not proof — confirm by flipping a byte inside the range,
recomputing, and checking a second known-good image. Expect a few coincidental "elsewhere"
matches; matches stored directly after their block are near-certain. Additive (sum32) matches
are reported for information but the engine currently implements CRC schemes only.
"""

import argparse
import struct
import sys
import zlib
from collections import defaultdict

MASK = 0xFFFFFFFF
BITREV_BYTE = bytes(int(f"{i:08b}"[::-1], 2) for i in range(256))


def bitrev32(v: int) -> int:
    return int(f"{v:032b}"[::-1], 2)


def boundary_list(size: int, align: int) -> list[int]:
    bounds = list(range(0, size, align))
    if bounds[-1] != size:
        bounds.append(size)
    return bounds


def crc_snapshots(data: memoryview, bounds: list[int], seed: int) -> dict[int, list[int]]:
    """For each start boundary, the running zlib.crc32 (from `seed`) at every later boundary."""
    out = {}
    for i, start in enumerate(bounds[:-1]):
        crc = seed
        snaps = []
        prev = start
        for end in bounds[i + 1:]:
            crc = zlib.crc32(data[prev:end], crc)
            prev = end
            snaps.append(crc)
        out[start] = snaps
    return out


# (label, reflected?, seed for zlib, transform of zlib output, JSON algorithm snippet)
# zlib.crc32(data, 0) == reflected CRC-32, init 0xFFFFFFFF, xorOut 0xFFFFFFFF.
# Seeding with 0xFFFFFFFF cancels the initial xor, giving internal init 0.
VARIANTS = [
    ("crc32 (reflected, init FFFFFFFF, xorOut FFFFFFFF)", True, 0,
     lambda c: c, '{"preset": "crc32"}'),
    ("crc32 jamcrc (reflected, init FFFFFFFF, xorOut 0)", True, 0,
     lambda c: c ^ MASK,
     '{"width": 32, "polynomial": "0x04C11DB7", "initialValue": "0xFFFFFFFF", "xorOut": "0x00000000", "reflectInput": true, "reflectOutput": true}'),
    ("crc32 (reflected, init 0, xorOut FFFFFFFF)", True, MASK,
     lambda c: c,
     '{"width": 32, "polynomial": "0x04C11DB7", "initialValue": "0x00000000", "xorOut": "0xFFFFFFFF", "reflectInput": true, "reflectOutput": true}'),
    ("crc32 (reflected, init 0, xorOut 0)", True, MASK,
     lambda c: c ^ MASK,
     '{"width": 32, "polynomial": "0x04C11DB7", "initialValue": "0x00000000", "xorOut": "0x00000000", "reflectInput": true, "reflectOutput": true}'),
    ("crc32-bzip2 (normal, init FFFFFFFF, xorOut FFFFFFFF)", False, 0,
     lambda c: bitrev32(c ^ MASK) ^ MASK, '{"preset": "crc32-bzip2"}'),
    ("crc32-mpeg2 (normal, init FFFFFFFF, xorOut 0)", False, 0,
     lambda c: bitrev32(c ^ MASK), '{"preset": "crc32-mpeg2"}'),
    ("crc32-posix (normal, init 0, xorOut FFFFFFFF)", False, MASK,
     lambda c: bitrev32(c ^ MASK) ^ MASK, '{"preset": "crc32-posix"}'),
    ("crc32 (normal, init 0, xorOut 0)", False, MASK,
     lambda c: bitrev32(c ^ MASK),
     '{"width": 32, "polynomial": "0x04C11DB7", "initialValue": "0x00000000", "xorOut": "0x00000000", "reflectInput": false, "reflectOutput": false}'),
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("bin", help="known-good image to scan")
    parser.add_argument("--align", type=lambda v: int(v, 0), default=0x10000,
                        help="block boundary alignment (default 0x10000)")
    parser.add_argument("--min-length", type=lambda v: int(v, 0), default=0x1000,
                        help="ignore candidate blocks shorter than this (default 0x1000)")
    args = parser.parse_args()

    with open(args.bin, "rb") as f:
        data = f.read()
    if len(data) < args.align:
        sys.exit(f"image ({len(data)} bytes) is smaller than one alignment unit")

    bounds = boundary_list(len(data), args.align)
    view = memoryview(data)
    reversed_view = memoryview(data.translate(BITREV_BYTE))
    print(f"{args.bin}: {len(data)} bytes, {len(bounds) - 1} x {args.align:#x} boundaries")

    # value -> list of (start, end, variant_index) candidates
    candidates = defaultdict(list)
    snapshots = {
        (True, 0): crc_snapshots(view, bounds, 0),
        (True, MASK): crc_snapshots(view, bounds, MASK),
        (False, 0): crc_snapshots(reversed_view, bounds, 0),
        (False, MASK): crc_snapshots(reversed_view, bounds, MASK),
    }
    for vi, (_, reflected, seed, transform, _) in enumerate(VARIANTS):
        table = snapshots[(reflected, seed)]
        for i, start in enumerate(bounds[:-1]):
            for j, crc in enumerate(table[start]):
                end = bounds[i + 1 + j]
                if end - start < args.min_length:
                    continue
                value = transform(crc) & MASK
                if value not in (0, MASK):
                    candidates[value].append((start, end, vi))

    # Additive 32-bit little-endian word sums via prefix sums at boundaries. Only 4-aligned
    # boundaries participate (the alignment default guarantees it; a stray file size may not).
    word_count = len(data) // 4
    words = struct.unpack(f"<{word_count}I", data[:word_count * 4])
    aligned = [b for b in bounds if b % 4 == 0]
    boundary_words = {b // 4 for b in aligned}
    prefix, total = {0: 0}, 0
    for idx, word in enumerate(words, start=1):
        total = (total + word) & MASK
        if idx in boundary_words:
            prefix[idx * 4] = total
    sum_candidates = defaultdict(list)
    for i, start in enumerate(aligned[:-1]):
        for end in aligned[i + 1:]:
            if end - start < args.min_length or start not in prefix or end not in prefix:
                continue
            block_sum = (prefix[end] - prefix[start]) & MASK
            for value, label in ((block_sum, "sum32"), ((-block_sum) & MASK, "-sum32")):
                if value not in (0, MASK):
                    sum_candidates[value].append((start, end, label))

    # Single pass over the image matching stored 32-bit words against all candidates.
    findings = []
    for offset in range(0, len(data) - 3, 4):
        le = struct.unpack_from("<I", data, offset)[0]
        be = struct.unpack_from(">I", data, offset)[0]
        for value, order in ((le, "littleEndian"), (be, "bigEndian")):
            for start, end, vi in candidates.get(value, ()):
                findings.append((start, end, offset, order, vi, None))
            for start, end, label in sum_candidates.get(value, ()):
                findings.append((start, end, offset, order, None, label))

    if not findings:
        print("no matches — try a smaller --align (e.g. 0x1000) or a different image")
        return 1

    # Stored-adjacent matches are near-certain; list them first.
    findings.sort(key=lambda f: (f[2] != f[1], f[0]))
    print(f"\n{len(findings)} candidate match(es); those stored directly after their block first:\n")
    for start, end, offset, order, vi, sum_label in findings:
        where = "directly after block" if offset == end else f"at {offset:#x}"
        inside = start <= offset < end
        note = "  [inside covered range — self-referential, verify manually]" if inside else ""
        if vi is not None:
            label, _, _, _, snippet = VARIANTS[vi]
            print(f"block {start:#x}..{end:#x}  stored {where} ({order})  {label}{note}")
            ranges = f'[{{"start": {start}, "length": {end - start}}}]'
            print(f'  {{"name": "Block {start:#x}", "ranges": {ranges}, "storedAt": {offset},'
                  f' "storedByteOrder": "{order}", "algorithm": {snippet}}}\n')
        else:
            print(f"block {start:#x}..{end:#x}  stored {where} ({order})  {sum_label}"
                  f"{note}  [additive — engine support not yet implemented]\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
