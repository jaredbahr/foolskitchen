#!/usr/bin/env python3
"""Derive lowered-backrest seat GLBs from the unchanged Kenney Furniture Kit files.

Python 3.9+ standard library only. Run from the repository root:
  python3 tools/derive_seat_backrests.py          # write the derived GLBs and manifest entries
  python3 tools/derive_seat_backrests.py --check  # fail if anything on disk differs

Jared (2026-10-28): seated guests' heads must not clip through seat backrests,
and guests are not leaned forward. Each derived seat keeps the kit file's
JSON, nodes, materials, UVs, index buffer and face order. Only vertices above
the seat top move: their height above the seat top is multiplied by `squash`
(a vertical squash of the backrest about the seat top). The seat, legs and
everything at or below the seat top keep their exact source bytes, so the
seat surface, footprint and plan silhouette do not change. Normals of moved
vertices get the matching inverse-transpose correction.

Every derived GLB also gets a schema-2 entry in tools/seated_head_backrests.json
with its own SHA-256 and complete face inventory. Its backrest face selection
is copied unchanged from the audited kit source (face order is identical).
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

KIT = "assets/kenney/furniture/"
OUT = "assets/props/seats/derived/"
MANIFEST = "tools/seated_head_backrests.json"

# source GLB -> (derived GLB, seat top in source units, squash factor, arms move).
# The seat top is the seat cushion's top. Without "arms move", every source
# face above it must be an audited backrest face (checked below). The lounge
# chair's arms and back block share edges up to 0.37, above its 0.23 seat, so
# its whole upper body is squashed together and keeps its proportions.
# Squash factors are measured with tools/seated_head_probe.gd.
SEATS = {
    "chair.glb": ("chair_low_back.glb", 0.24, 0.52, False),
    "chairCushion.glb": ("chairCushion_low_back.glb", 0.24, 0.58, False),
    "chairRounded.glb": ("chairRounded_low_back.glb", 0.22, 0.52, False),
    "chairModernCushion.glb": ("chairModernCushion_low_back.glb", 0.24, 0.55, False),
    "chairModernFrameCushion.glb": ("chairModernFrameCushion_low_back.glb", 0.24, 0.55, False),
    "loungeChair.glb": ("loungeChair_low_back.glb", 0.23, 0.52, True),
    "bench.glb": ("bench_low_back.glb", 0.24, 0.52, False),
    "benchCushion.glb": ("benchCushion_low_back.glb", 0.24, 0.55, False),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def split_glb(data):
    magic, version, length = struct.unpack_from("<III", data)
    require(magic == 0x46546C67 and version == 2 and length == len(data), "invalid GLB2 header")
    json_size, json_kind = struct.unpack_from("<II", data, 12)
    require(json_kind == 0x4E4F534A, "expected JSON chunk first")
    document = json.loads(data[20:20 + json_size].decode("utf-8"))
    at = 20 + json_size
    bin_size, bin_kind = struct.unpack_from("<II", data, at)
    require(bin_kind == 0x004E4942 and at + 8 + bin_size == len(data), "expected one BIN chunk last")
    require(len(document["buffers"]) == 1 and "uri" not in document["buffers"][0], "expected one embedded buffer")
    return document, bytearray(data[at + 8:])


def join_glb(document, binary):
    text = json.dumps(document, separators=(",", ":"), sort_keys=False).encode("utf-8")
    text += b" " * ((4 - len(text) % 4) % 4)
    binary = bytes(binary) + b"\0" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(text) + 8 + len(binary)
    return (struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(text), 0x4E4F534A) + text
            + struct.pack("<II", len(binary), 0x004E4942) + binary)


def vec3_slots(document, number):
    entry = document["accessors"][number]
    require(entry["type"] == "VEC3" and entry["componentType"] == 5126 and "sparse" not in entry,
            "expected float VEC3 accessor")
    view = document["bufferViews"][entry["bufferView"]]
    stride = view.get("byteStride", 12)
    base = view.get("byteOffset", 0) + entry.get("byteOffset", 0)
    return entry, [base + index * stride for index in range(entry["count"])]


def indices(document, binary, number):
    entry = document["accessors"][number]
    code, width = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4)}[entry["componentType"]]
    view = document["bufferViews"][entry["bufferView"]]
    stride = view.get("byteStride", width)
    base = view.get("byteOffset", 0) + entry.get("byteOffset", 0)
    return [struct.unpack_from("<" + code, binary, base + index * stride)[0] for index in range(entry["count"])]


def f32(value):
    return struct.unpack("<f", struct.pack("<f", value))[0]


def derive(source_bytes, seat_top, squash, arms_move, backrest_faces):
    """Returns derived GLB bytes. Squash 0 is refused: a backrest must remain."""
    require(0.0 < squash <= 1.0, "squash must keep a backrest (0 < squash <= 1)")
    # Kit files store the seat top as neighbouring float32 values (0.24 is both
    # 0.2399999946 and 0.2400000095); anything within 1e-5 counts as the seat.
    limit = seat_top + 1e-5
    document, binary = split_glb(source_bytes)
    selected = set(backrest_faces)
    face = 0
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            require(primitive.get("mode", 4) == 4 and "indices" in primitive, "expected indexed triangles")
            position, slots = vec3_slots(document, primitive["attributes"]["POSITION"])
            normal_slots = vec3_slots(document, primitive["attributes"]["NORMAL"])[1]
            order = indices(document, binary, primitive["indices"])
            above = set()
            for start in range(0, len(order), 3):
                corners = order[start:start + 3]
                heights = [struct.unpack_from("<3f", binary, slots[i])[1] for i in corners]
                # Only audited backrest faces may rise above the seat top.
                require(arms_move or face in selected or max(heights) <= limit, "non-backrest face above the seat top: face %d heights %s" % (face, heights))
                above.update(i for i, y in zip(corners, heights) if y > limit)
                face += 1
            for index in sorted(above):
                x, y, z = struct.unpack_from("<3f", binary, slots[index])
                # Round to 0.1 mm so no derived height lands on a half step of the
                # engine's 0.0001 face snap (see tools/seated_head_backrests.gd).
                struct.pack_into("<3f", binary, slots[index], x, f32(round(seat_top + (y - seat_top) * squash, 4)), z)
                nx, ny, nz = struct.unpack_from("<3f", binary, normal_slots[index])
                ny /= squash
                length = math.sqrt(nx * nx + ny * ny + nz * nz)
                struct.pack_into("<3f", binary, normal_slots[index], nx / length, ny / length, nz / length)
            points = [struct.unpack_from("<3f", binary, slot) for slot in slots]
            position["min"] = [min(p[a] for p in points) for a in range(3)]
            position["max"] = [max(p[a] for p in points) for a in range(3)]
    return join_glb(document, binary)


def face_inventory(data):
    document, binary = split_glb(data)
    faces = []
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            _, slots = vec3_slots(document, primitive["attributes"]["POSITION"])
            for index in indices(document, binary, primitive["indices"]):
                if not faces or len(faces[-1]) == 9:
                    faces.append([])
                faces[-1].extend(struct.unpack_from("<3f", binary, slots[index]))
    return [struct.pack("<9f", *f).hex() for f in faces]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true", help="verify files on disk, write nothing")
    arguments = parser.parse_args()
    root = arguments.root.resolve()
    manifest_path = root / MANIFEST
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    sources = manifest["sources"]
    stale = []
    for name, (derived_name, seat_top, squash, arms_move) in SEATS.items():
        kit_reference = "res://" + KIT + name
        kit = sources[kit_reference]
        source_bytes = (root / KIT / name).read_bytes()
        require(hashlib.sha256(source_bytes).hexdigest() == kit["sha256"], "kit source changed: " + name)
        data = derive(source_bytes, seat_top, squash, arms_move, kit["backrest_faces"])
        entry = {"sha256": hashlib.sha256(data).hexdigest(), "faces": face_inventory(data),
                 "backrest_faces": list(kit["backrest_faces"]),
                 "audit": "Derived by tools/derive_seat_backrests.py from %s (sha256 %s): vertices above "
                          "the seat top y=%s squashed by %s%s; face order and backrest selection copied "
                          "from the kit entry." % (name, kit["sha256"], seat_top, squash,
                                                   " (arms included)" if arms_move else "")}
        target = root / OUT / derived_name
        reference = "res://" + OUT + derived_name
        if not target.exists() or target.read_bytes() != data:
            stale.append(str(target.relative_to(root)))
        if sources.get(reference) != entry:
            stale.append(MANIFEST + " entry " + reference)
        if not arguments.check:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            sources[reference] = entry
    if arguments.check:
        if stale:
            print("stale derived seats:\n  " + "\n  ".join(stale))
            return 1
        print("derived seats up to date")
        return 0
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("wrote %d derived seats" % len(SEATS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
