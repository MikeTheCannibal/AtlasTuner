#!/usr/bin/env python3
"""
List the MEASUREMENT objects in a BMW/Bosch A2L with their RAM address, data type, byte order and
decoded linear scale factor — the inputs needed to build an `ENETChannelMap` for live logging.

Scaling: A2L COMPU_METHODs here are RAT_FUNC with coefficients [a,b,c,d,e,f] and a=c=d=e=0, so the
ECU→physical factor is f/b (offset 0). Example: relative charge b=128,f=3 -> 3/128 = 0.0234375.

Usage:
    python3 Tools/a2l_measurements.py vehicle.a2l [name-substring]
"""

import re
import sys

A2L_TYPE_TO_SWIFT = {
    "UBYTE": "uint8", "SBYTE": "int8",
    "UWORD": "uint16", "SWORD": "int16",
    "ULONG": "uint32", "SLONG": "int32",
    "FLOAT32_IEEE": "float32",
}


def parse(path):
    text = open(path, encoding="latin-1").read()

    compu = {}
    for m in re.finditer(r"/begin COMPU_METHOD\s+(\S+)\s+\"[^\"]*\"\s+\S+(.*?)/end COMPU_METHOD", text, re.S):
        name, body = m.group(1), m.group(2)
        unit = ""
        um = re.search(r'\bUNIT\s+"([^"]*)"', body)
        if um:
            unit = um.group(1)
        factor = None
        cf = re.search(r"COEFFS\s+([\-\d.eE]+)\s+([\-\d.eE]+)\s+([\-\d.eE]+)\s+([\-\d.eE]+)\s+([\-\d.eE]+)\s+([\-\d.eE]+)", body)
        cl = re.search(r"COEFFS_LINEAR\s+([\-\d.eE]+)\s+([\-\d.eE]+)", body)
        if cf:
            a, b, c, d, e, f = (float(x) for x in cf.groups())
            if a == 0 and c == 0 and d == 0 and e == 0 and b != 0:
                factor = f / b
        elif cl:
            factor = float(cl.group(1))
        compu[name] = (factor, unit)

    rows = []
    pattern = (r"/begin MEASUREMENT\s+(\S+)\s+\"([^\"]*)\"\s+(\S+)\s+(\S+)\s+\S+\s+\S+\s+"
               r"[\-\d.eE]+\s+[\-\d.eE]+(.*?)/end MEASUREMENT")
    for m in re.finditer(pattern, text, re.S):
        name, desc, dtype, conv, body = m.groups()
        addr = re.search(r"ECU_ADDRESS\s+(0x[0-9A-Fa-f]+)", body)
        bo = re.search(r"BYTE_ORDER\s+(\S+)", body)
        factor, unit = compu.get(conv, (None, ""))
        rows.append(dict(
            name=name, desc=desc, dtype=dtype,
            swift=A2L_TYPE_TO_SWIFT.get(dtype, "?"),
            addr=addr.group(1) if addr else "?",
            order="little" if (bo is None or bo.group(1) == "MSB_LAST") else "big",
            factor=factor, unit=unit,
        ))
    return rows


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    rows = parse(sys.argv[1])
    needle = sys.argv[2].lower() if len(sys.argv) > 2 else None
    print(f"{'name':32} {'address':>12} {'type':8} {'factor':>12}  description")
    for r in rows:
        if needle and needle not in r["name"].lower() and needle not in r["desc"].lower():
            continue
        factor = f"{r['factor']:.6g}" if r["factor"] is not None else "?"
        print(f"{r['name'][:32]:32} {r['addr']:>12} {r['swift']:8} {factor:>12}  {r['desc'][:46]}")
    print(f"\n{len(rows)} measurements")


if __name__ == "__main__":
    main()
