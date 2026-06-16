#!/usr/bin/env python3
"""
Convert a TunerPro XDF (as exported by MHD+) into an Atlas Tune `DefinitionPackage` JSON that the
engine loads at runtime via `Bundle.module`.

The output JSON matches the Codable shape of `DefinitionPackage` / `TableDefinition` /
`AxisDefinition` exactly, including Swift's synthesized enum encoding for `AxisDefinition.Source`
(`{"stored": {...}}` / `{"fixed": {...}}`).

Usage:
    python3 Tools/xdf_to_definition.py <input.xdf> <output.json>

Identification metadata (image size, signatures, version banner) is injected here so the generated
package is self-contained and the catalog can load it directly.

Notes / fidelity:
- XDF MATH equations are reduced to a linear `display = raw*factor + offset` by sampling the
  expression; non-linear equations are linearly approximated and flagged in the description.
- `mmedtypeflags`: bit 0x01 = signed, bit 0x02 = little-endian (MG1 is always LE), bit 0x10000 =
  float. Element size comes from `mmedelementsizebits`.
- `CATEGORYMEM category` == header CATEGORY index (decimal) + 1.
- Tables whose data or axes fall outside the 8 MiB image are skipped (reported).
"""

import json
import re
import sys
import xml.etree.ElementTree as ET

IMAGE_SIZE = 8 * 1024 * 1024

# Identification reconciled against the real G87 / MG1CS049 image.
IDENTITY = {
    "id": "bmw.s58.mg1cs049.cb011",
    "family": "S58 / MG1CS049 (DME 8.6.S)",
    "calibrationVersion": "CB_011_253.23.0_1.2.0",
    "expectedImageSizes": [IMAGE_SIZE],
    "versionField": {"address": 0x29000, "length": 21},
    "signatures": [
        {"address": 0x5FE1E, "pattern": list(b"#DME_86T0#CX#BTL#MDG1_I35UP"),
         "label": "MG1CS049 build descriptor"},
        {"address": 0x7FFE51, "pattern": list(b"DME8.6.S_S58_G87"),
         "label": "DME 8.6.S S58 G87 marker"},
    ],
}

SAFE_EQ = re.compile(r'^[0-9Xx.+\-*/() eE]*$')


def linear_from_equation(eq):
    """Return (factor, offset, is_linear) from a MATH equation, or None if unusable."""
    eq = (eq or "X").strip()
    if not SAFE_EQ.match(eq):
        return None
    def f(xv):
        try:
            return float(eval(eq, {"__builtins__": {}}, {"X": xv, "x": xv}))
        except Exception:
            return None
    f0, f1, f2 = f(0.0), f(1.0), f(2.0)
    if f0 is None or f1 is None:
        return None
    factor, offset = f1 - f0, f0
    is_linear = True
    if f2 is not None:
        if abs((offset + factor * 2.0) - f2) > 1e-6 * max(1.0, abs(f2)):
            is_linear = False
    return factor, offset, is_linear


def data_type(bits, flags):
    signed = bool(flags & 0x1)
    is_float = bool(flags & 0x10000)
    if bits == 8:
        return "int8" if signed else "uint8"
    if bits == 16:
        return "int16" if signed else "uint16"
    if bits == 32:
        return "float32" if is_float else ("int32" if signed else "uint32")
    return None


def byte_width(dt):
    return {"int8": 1, "uint8": 1, "int16": 2, "uint16": 2,
            "int32": 4, "uint32": 4, "float32": 4}[dt]


def bucket(name):
    n = name.lower()
    if "safety" in n or "protect" in n:
        return "safety"
    if any(k in n for k in ("fuel", "flex", "maf", "ethanol", "rail", "inject", "lambda", "afr", "stft", "ltft")):
        return "fuel"
    if any(k in n for k in ("ignition", "knock", "timing", "spark")):
        return "ignition"
    if any(k in n for k in ("boost", "wgdc", "wastegate", "load", "throttle", "antilag", "charge")):
        return "boost"
    if any(k in n for k in ("torque", "limit", "rev ")):
        return "torque"
    if any(k in n for k in ("cool", "temp", "egt", "oil pressure", "sensor", "idc", "overboost")):
        return "safety"
    return "other"


def text_of(el, tag, default=""):
    child = el.find(tag)
    return child.text.strip() if child is not None and child.text else default


def scaling_of(axis_el):
    math = axis_el.find("MATH")
    eq = math.get("equation") if math is not None else "X"
    lin = linear_from_equation(eq)
    decimals = int(text_of(axis_el, "decimalpl", "2") or "2")
    if lin is None:
        return {"factor": 1.0, "offset": 0.0, "decimals": decimals}, True
    factor, offset, is_linear = lin
    return {"factor": factor, "offset": offset, "decimals": decimals}, is_linear


def embedded(axis_el):
    return axis_el.find("EMBEDDEDDATA")


def build_axis(axis_el, axis_id, name_prefix):
    """Return (axisDict, in_bounds) or (None, True) if the axis is absent."""
    if axis_el is None:
        return None, True
    units = text_of(axis_el, "units", "")
    scaling, _ = scaling_of(axis_el)
    ed = embedded(axis_el)

    if ed is not None and ed.get("mmedaddress"):
        addr = int(ed.get("mmedaddress"), 16)
        bits = int(ed.get("mmedelementsizebits", "16"))
        flags = int(ed.get("mmedtypeflags", "0x2"), 16)
        count = int(ed.get("mmedcolcount", "1"))
        dt = data_type(bits, flags)
        if dt is None or count <= 0:
            return None, True
        in_bounds = addr + count * byte_width(dt) <= IMAGE_SIZE
        axis = {
            "id": f"{name_prefix}.{axis_id}",
            "name": units or axis_id.upper(),
            "unit": units,
            "count": count,
            "source": {"stored": {"address": addr, "dataType": dt, "scaling": scaling}},
        }
        return axis, in_bounds

    labels = axis_el.findall("LABEL")
    values = []
    for lb in labels:
        try:
            values.append(float(lb.get("value")))
        except (TypeError, ValueError):
            pass
    if values:
        axis = {
            "id": f"{name_prefix}.{axis_id}",
            "name": units or axis_id.upper(),
            "unit": units,
            "count": len(values),
            "source": {"fixed": {"values": values}},
        }
        return axis, True
    return None, True


def convert(xdf_path):
    tree = ET.parse(xdf_path)
    root = tree.getroot()

    categories = {}
    for cat in root.iter("CATEGORY"):
        idx = int(cat.get("index"), 16)
        categories[idx + 1] = cat.get("name")  # CATEGORYMEM uses index+1

    tables = []
    stats = {"total": 0, "converted": 0, "skip_no_data": 0,
             "skip_bounds": 0, "skip_dtype": 0, "nonlinear": 0}

    for i, tbl in enumerate(root.iter("XDFTABLE")):
        stats["total"] += 1
        title = text_of(tbl, "title", f"Table {i}")
        desc = text_of(tbl, "description", "")

        cat_mem = tbl.find("CATEGORYMEM")
        cat_name = "Other"
        if cat_mem is not None and cat_mem.get("category"):
            cat_name = categories.get(int(cat_mem.get("category")), "Other")

        axes = {a.get("id"): a for a in tbl.findall("XDFAXIS")}
        z = axes.get("z")
        if z is None:
            stats["skip_no_data"] += 1
            continue
        ed = embedded(z)
        if ed is None or not ed.get("mmedaddress"):
            stats["skip_no_data"] += 1
            continue

        addr = int(ed.get("mmedaddress"), 16)
        bits = int(ed.get("mmedelementsizebits", "16"))
        flags = int(ed.get("mmedtypeflags", "0x2"), 16)
        rows = int(ed.get("mmedrowcount", "1"))
        cols = int(ed.get("mmedcolcount", "1"))
        dt = data_type(bits, flags)
        if dt is None:
            stats["skip_dtype"] += 1
            continue

        if addr + rows * cols * byte_width(dt) > IMAGE_SIZE:
            stats["skip_bounds"] += 1
            continue

        scaling, is_linear = scaling_of(z)
        if not is_linear:
            stats["nonlinear"] += 1
            desc = (desc + " (non-linear scaling linearly approximated)").strip()

        prefix = f"xdf{i:04d}"
        x_axis, x_ok = build_axis(axes.get("x"), "x", prefix) if cols > 1 else (None, True)
        y_axis, y_ok = build_axis(axes.get("y"), "y", prefix) if rows > 1 else (None, True)
        if not (x_ok and y_ok):
            stats["skip_bounds"] += 1
            continue

        table = {
            "id": prefix,
            "name": title,
            "description": desc,
            "category": bucket(cat_name),
            "subcategory": cat_name,
            "address": addr,
            "dataType": dt,
            "scaling": scaling,
            "unit": text_of(z, "units", ""),
            "rows": rows,
            "columns": cols,
        }
        if x_axis is not None:
            table["xAxis"] = x_axis
        if y_axis is not None:
            table["yAxis"] = y_axis

        zmin, zmax = text_of(z, "min", ""), text_of(z, "max", "")
        if zmin and zmax:
            try:
                lo, hi = float(zmin), float(zmax)
                if lo < hi:
                    table["valueRangeLower"] = lo
                    table["valueRangeUpper"] = hi
            except ValueError:
                pass

        tables.append(table)
        stats["converted"] += 1

    package = dict(IDENTITY)
    package["tables"] = tables
    return package, stats


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    package, stats = convert(sys.argv[1])
    with open(sys.argv[2], "w") as f:
        json.dump(package, f, separators=(",", ":"))
    print("Conversion stats:")
    for k, v in stats.items():
        print(f"  {k:14s}: {v}")
    print(f"  output tables : {len(package['tables'])}")


if __name__ == "__main__":
    main()
