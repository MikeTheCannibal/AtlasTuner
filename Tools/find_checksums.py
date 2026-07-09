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

The trouble with one image: a single scan produces mostly COINCIDENTAL matches. There are tens
of thousands of candidate block ranges, ten algorithms and millions of stored 32-bit words, so
hundreds of random 32-bit collisions are expected by chance alone — a raw hit count near that
noise floor means nothing was really found. The fix is two known-good images of the SAME family
but DIFFERENT data (two stock reads from different cars, or a re-read):

    Tools/find_checksums.py --compare carA.bin carB.bin

A real checksum validates at the same (range, algorithm, stored offset, endianness) in BOTH
images even though its stored value differs; a coincidence would have to recur at the exact same
coordinates in the second image (~2**-32), so the noise floor collapses to near zero. Only the
intersection is printed, ranked with the strongest evidence — different underlying block data —
first.

Caveats: additive (sum32) matches are reported for information but the engine currently
implements CRC schemes only. Even a compare-confirmed candidate should be sanity-checked by
editing a byte in range and re-flashing on the bench before you trust it.
"""

import argparse
import struct
import sys
import zlib
from collections import defaultdict, namedtuple

MASK = 0xFFFFFFFF
BITREV_BYTE = bytes(int(f"{i:08b}"[::-1], 2) for i in range(256))

# A single candidate match. `vi` indexes VARIANTS for a CRC hit; for an additive hit `vi` is
# None and `sum_label` is set. `value` is the matched 32-bit word (differs per image).
Finding = namedtuple("Finding", "start end offset order vi sum_label value")


def coordinates(f: Finding):
    """Location+algorithm identity of a finding, independent of the stored value. Two images
    agree here iff the same block/algorithm/offset/endianness validates in both."""
    return (f.start, f.end, f.offset, f.order, f.vi, f.sum_label)


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


def scan(data: bytes, align: int, min_length: int) -> list[Finding]:
    """All candidate checksum matches in one image."""
    bounds = boundary_list(len(data), align)
    view = memoryview(data)
    reversed_view = memoryview(data.translate(BITREV_BYTE))

    # value -> list of (start, end, variant_index)
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
                if end - start < min_length:
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
            if end - start < min_length or start not in prefix or end not in prefix:
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
                findings.append(Finding(start, end, offset, order, vi, None, value))
            for start, end, label in sum_candidates.get(value, ()):
                findings.append(Finding(start, end, offset, order, None, label, value))
    return findings


def describe(f: Finding) -> str:
    """Human line + (for CRC hits) a paste-ready JSON snippet."""
    where = "directly after block" if f.offset == f.end else f"at {f.offset:#x}"
    note = "  [inside covered range — self-referential, verify manually]" \
        if f.start <= f.offset < f.end else ""
    if f.vi is not None:
        label, _, _, _, snippet = VARIANTS[f.vi]
        ranges = f'[{{"start": {f.start}, "length": {f.end - f.start}}}]'
        return (f"block {f.start:#x}..{f.end:#x}  stored {where} ({f.order})  {label}{note}\n"
                f'  {{"name": "Block {f.start:#x}", "ranges": {ranges}, "storedAt": {f.offset},'
                f' "storedByteOrder": "{f.order}", "algorithm": {snippet}}}')
    return (f"block {f.start:#x}..{f.end:#x}  stored {where} ({f.order})  {f.sum_label}"
            f"{note}  [additive — engine support not yet implemented]")


def run_single(path: str, align: int, min_length: int) -> int:
    with open(path, "rb") as fh:
        data = fh.read()
    if len(data) < align:
        sys.exit(f"image ({len(data)} bytes) is smaller than one alignment unit")
    bounds = boundary_list(len(data), align)
    print(f"{path}: {len(data)} bytes, {len(bounds) - 1} x {align:#x} boundaries")

    findings = scan(data, align, min_length)
    if not findings:
        print("no matches — try a smaller --align (e.g. 0x1000) or a different image")
        return 1

    # Stored-adjacent matches are the least likely to be coincidental; list them first.
    findings.sort(key=lambda f: (f.offset != f.end, f.start))
    print(f"\n{len(findings)} candidate match(es); those stored directly after their block first.")
    print("NOTE: expect this to be dominated by coincidence — use --compare with a second "
          "known-good image to separate real checksums from noise.\n")
    for f in findings:
        print(describe(f) + "\n")
    return 0


def run_compare(path_a: str, path_b: str, align: int, min_length: int) -> int:
    with open(path_a, "rb") as fh:
        data_a = fh.read()
    with open(path_b, "rb") as fh:
        data_b = fh.read()
    if len(data_a) != len(data_b):
        sys.exit(f"images differ in size ({len(data_a)} vs {len(data_b)}); a checksum layout is "
                 "size-specific, so compare two reads of the same ROM family")
    if len(data_a) < align:
        sys.exit(f"image ({len(data_a)} bytes) is smaller than one alignment unit")
    if data_a == data_b:
        sys.exit("the two images are identical — comparison needs different data to filter "
                 "coincidences; supply two DIFFERENT known-good reads")

    bounds = boundary_list(len(data_a), align)
    print(f"comparing:\n  A {path_a}\n  B {path_b}")
    print(f"{len(data_a)} bytes each, {len(bounds) - 1} x {align:#x} boundaries")

    findings_a = scan(data_a, align, min_length)
    by_coord_b = {coordinates(f): f for f in scan(data_b, align, min_length)}
    print(f"\nimage A: {len(findings_a)} raw candidates   image B: {len(by_coord_b)} raw candidates")

    survivors = [(a, by_coord_b[c]) for a in findings_a
                 if (c := coordinates(a)) in by_coord_b]
    if not survivors:
        print("\nno candidate survived in both images — nothing here behaves like a real "
              "checksum at this alignment. Try a smaller --align (e.g. 0x1000, 0x400).")
        return 1

    # A survivor whose covered block DIFFERS between the two images is strong evidence: the
    # stored word tracked the data change. Identical block data is weaker (the match could
    # persist trivially). Rank stronger evidence, then stored-adjacent, first.
    def block_differs(a: Finding) -> bool:
        return data_a[a.start:a.end] != data_b[a.start:a.end]

    survivors.sort(key=lambda pair: (not block_differs(pair[0]), pair[0].offset != pair[0].end,
                                     pair[0].start))
    strong = sum(1 for a, _ in survivors if block_differs(a))
    print(f"{len(survivors)} candidate(s) confirmed in BOTH images "
          f"({strong} with differing block data — strongest evidence):\n")
    for a, b in survivors:
        evidence = "block data DIFFERS between A/B — strong" if block_differs(a) \
            else "block data identical in A/B — weak, may be coincidental"
        print(describe(a))
        print(f"  stored value  A={a.value:#010x}  B={b.value:#010x}   [{evidence}]\n")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("bin", nargs="?", help="known-good image to scan")
    parser.add_argument("--compare", nargs=2, metavar=("A", "B"),
                        help="two known-good images of the same ROM; print only checksums "
                             "confirmed in both (filters coincidental matches)")
    parser.add_argument("--align", type=lambda v: int(v, 0), default=0x10000,
                        help="block boundary alignment (default 0x10000)")
    parser.add_argument("--min-length", type=lambda v: int(v, 0), default=0x1000,
                        help="ignore candidate blocks shorter than this (default 0x1000)")
    args = parser.parse_args()

    if bool(args.bin) == bool(args.compare):
        parser.error("give exactly one of: a single image, or --compare A B")
    if args.compare:
        return run_compare(*args.compare, args.align, args.min_length)
    return run_single(args.bin, args.align, args.min_length)


if __name__ == "__main__":
    sys.exit(main())
