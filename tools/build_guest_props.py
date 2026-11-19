"""Build the tourist sun hat and the office lanyard (#661).

python3 tools/build_guest_props.py
Pure standard-library Python: no Blender, no downloads, no random draws, so a
rebuild writes the same bytes. Writes assets/made/people/sun_hat.glb and
assets/made/people/lanyard.glb.

Both are chunky flat-shaded low-poly pieces in the Mini Characters style,
coloured only through the characters kit's own colormap.png (every face's UVs
point at one swatch; the image is referenced by relative path, never copied).
Units are the kit's source units (the same ones the courier cap and the head
bone use), glTF Y-up, front toward +Z (the models' front before the pivot turn).

* sun_hat.glb: origin at the middle of the hat's underside. The game lifts it
  to each model's head top and sinks it into the hair (person.gd).
* lanyard.glb: origin at the torso bone's rest position, so it rides the chest
  through every clip. It is a strap in a V, a card, and a white shirt front.
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "made" / "people"
COLORMAP_URI = "../../kenney/characters/Textures/colormap.png"
SIZE = 512.0

# Colormap texels (x, y) picked as the nearest kit swatch to each colour named.
SWATCH = {
    "straw": (32, 328),       # pale wheat straw (248, 212, 170)
    "band": (96, 508),        # slate navy hat band (86, 92, 116)
    "strap": (264, 264),      # lanyard red (207, 83, 79)
    "white": (296, 392),      # card and shirt front (252, 252, 253)
    "ink": (168, 504),        # card photo and clip (59, 62, 74)
}

# The torso bone's rest position in model space (see the kit's glTF nodes).
TORSO_ORIGIN = (0.0, 0.17625, -0.02875)
# Chest front in model space. The kit's torsos reach z 0.08 to 0.12 over the
# chest, so the strap sits a hair outside the widest of them.
CHEST_Z = 0.118

SEGMENTS = 10


class Mesh:
    def __init__(self) -> None:
        self.positions: list[tuple[float, float, float]] = []
        self.normals: list[tuple[float, float, float]] = []
        self.uvs: list[tuple[float, float]] = []
        self.indices: list[int] = []

    def face(self, points: list[tuple[float, float, float]], swatch: str) -> None:
        """One flat polygon, wound counter-clockwise seen from outside."""
        a, b, c = points[0], points[1], points[2]
        u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        length = math.sqrt(sum(x * x for x in n)) or 1.0
        n = (n[0] / length, n[1] / length, n[2] / length)
        x, y = SWATCH[swatch]
        uv = ((x + 0.5) / SIZE, (y + 0.5) / SIZE)
        base = len(self.positions)
        for p in points:
            self.positions.append(p)
            self.normals.append(n)
            self.uvs.append(uv)
        for i in range(1, len(points) - 1):
            self.indices += [base, base + i, base + i + 1]

    def triangles(self) -> int:
        return len(self.indices) // 3


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def frustum(mesh: Mesh, centre, r_bottom: float, r_top: float, height: float, swatch: str,
            segments: int = SEGMENTS, cap_bottom: bool = True) -> None:
    """A vertical prism with a flat top; y runs from centre.y up by height."""
    cx, cy, cz = centre
    ring_b = []
    ring_t = []
    for i in range(segments):
        angle = 2.0 * math.pi * i / segments
        ring_b.append((cx + r_bottom * math.sin(angle), cy, cz + r_bottom * math.cos(angle)))
        ring_t.append((cx + r_top * math.sin(angle), cy + height, cz + r_top * math.cos(angle)))
    for i in range(segments):
        j = (i + 1) % segments
        mesh.face([ring_b[i], ring_t[i], ring_t[j], ring_b[j]], swatch)
    mesh.face(list(reversed(ring_t)), swatch)
    if cap_bottom:
        mesh.face(ring_b, swatch)


def oriented_box(mesh: Mesh, start, end, width: float, thick: float, swatch: str) -> None:
    """A flat strip from start to end, `width` across and `thick` deep (toward +Z)."""
    d = (end[0] - start[0], end[1] - start[1], end[2] - start[2])
    length = math.sqrt(sum(x * x for x in d))
    d = (d[0] / length, d[1] / length, d[2] / length)
    # Width runs along the strip's side axis: the direction crossed with +Z.
    side = (d[1], -d[0], 0.0)
    sl = math.hypot(side[0], side[1]) or 1.0
    side = (side[0] / sl * width / 2.0, side[1] / sl * width / 2.0, 0.0)
    depth = (0.0, 0.0, thick / 2.0)
    corners = {}
    for ex, e in (("s", start), ("e", end)):
        for sx in (-1, 1):
            for sz in (-1, 1):
                corners[(ex, sx, sz)] = (e[0] + sx * side[0] + sz * depth[0], e[1] + sx * side[1] + sz * depth[1],
                                         e[2] + sx * side[2] + sz * depth[2])
    c = corners
    mesh.face([c["s", -1, 1], c["s", 1, 1], c["e", 1, 1], c["e", -1, 1]], swatch)      # front (+Z)
    mesh.face([c["s", 1, -1], c["s", -1, -1], c["e", -1, -1], c["e", 1, -1]], swatch)  # back
    mesh.face([c["s", 1, 1], c["s", 1, -1], c["e", 1, -1], c["e", 1, 1]], swatch)      # +side
    mesh.face([c["s", -1, -1], c["s", -1, 1], c["e", -1, 1], c["e", -1, -1]], swatch)  # -side
    mesh.face([c["e", -1, 1], c["e", 1, 1], c["e", 1, -1], c["e", -1, -1]], swatch)    # end
    mesh.face([c["s", -1, -1], c["s", 1, -1], c["s", 1, 1], c["s", -1, 1]], swatch)    # start


def box(mesh: Mesh, centre, size, swatch: str) -> None:
    cx, cy, cz = centre
    hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    p = lambda sx, sy, sz: (cx + sx * hx, cy + sy * hy, cz + sz * hz)
    mesh.face([p(-1, -1, 1), p(1, -1, 1), p(1, 1, 1), p(-1, 1, 1)], swatch)
    mesh.face([p(1, -1, -1), p(-1, -1, -1), p(-1, 1, -1), p(1, 1, -1)], swatch)
    mesh.face([p(1, -1, 1), p(1, -1, -1), p(1, 1, -1), p(1, 1, 1)], swatch)
    mesh.face([p(-1, -1, -1), p(-1, -1, 1), p(-1, 1, 1), p(-1, 1, -1)], swatch)
    mesh.face([p(-1, 1, 1), p(1, 1, 1), p(1, 1, -1), p(-1, 1, -1)], swatch)
    mesh.face([p(-1, -1, -1), p(1, -1, -1), p(1, -1, 1), p(-1, -1, 1)], swatch)


def sun_hat(band: str = "band") -> Mesh:
    """A small straw hat: a thin round brim, a short crown and a navy band."""
    mesh = Mesh()
    frustum(mesh, (0.0, 0.0, 0.0), 0.2, 0.2, 0.022, "straw")            # brim
    frustum(mesh, (0.0, 0.022, 0.0), 0.155, 0.145, 0.05, "straw", cap_bottom=False)  # crown
    frustum(mesh, (0.0, 0.022, 0.0), 0.162, 0.153, 0.026, band, cap_bottom=False)    # band
    return mesh


def lanyard() -> Mesh:
    """Strap in a V, a hanging card and a white shirt front, in torso-bone space."""
    mesh = Mesh()
    ox, oy, oz = TORSO_ORIGIN

    def at(x: float, y: float, z: float):
        return (x - ox, y - oy, z - oz)

    zs = CHEST_Z
    # White shirt front: a slim panel from the collar to the belly.
    box(mesh, at(0.0, 0.265, zs - 0.004), (0.17, 0.23, 0.012), "white")
    # Strap: from each side of the neck, down the chest, to the card clip.
    for sign in (-1.0, 1.0):
        oriented_box(mesh, at(sign * 0.095, 0.345, zs + 0.002), at(sign * 0.012, 0.215, zs + 0.012), 0.042, 0.012, "strap")
    box(mesh, at(0.0, 0.208, zs + 0.012), (0.04, 0.026, 0.014), "ink")           # clip
    box(mesh, at(0.0, 0.158, zs + 0.012), (0.115, 0.15, 0.014), "white")          # card
    box(mesh, at(0.0, 0.158, zs + 0.021), (0.115, 0.15, 0.004), "white")
    box(mesh, at(-0.022, 0.178, zs + 0.0245), (0.05, 0.05, 0.004), "ink")         # photo
    box(mesh, at(0.0, 0.122, zs + 0.0245), (0.085, 0.018, 0.004), "strap")        # name stripe
    return mesh


def pad(data: bytes) -> bytes:
    return data + b"\0" * (-len(data) % 4)


def glb(mesh: Mesh, name: str) -> bytes:
    pos = b"".join(struct.pack("<fff", *p) for p in mesh.positions)
    nor = b"".join(struct.pack("<fff", *n) for n in mesh.normals)
    uv = b"".join(struct.pack("<ff", *t) for t in mesh.uvs)
    idx = pad(b"".join(struct.pack("<H", i) for i in mesh.indices))
    blob = pos + nor + uv + idx
    xs = [p[0] for p in mesh.positions]
    ys = [p[1] for p in mesh.positions]
    zs = [p[2] for p in mesh.positions]
    n = len(mesh.positions)
    doc = {
        "asset": {"version": "2.0", "generator": "tools/build_guest_props.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0}],
        "meshes": [{"name": name, "primitives": [{
            "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "material": 0}]}],
        "materials": [{"name": "colormap", "doubleSided": True,
                       "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0}}],
        "textures": [{"sampler": 0, "source": 0}],
        "samplers": [{"magFilter": 9728, "minFilter": 9728, "wrapS": 10497, "wrapT": 10497}],
        "images": [{"uri": COLORMAP_URI}],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": n, "type": "VEC3",
             "min": [min(xs), min(ys), min(zs)], "max": [max(xs), max(ys), max(zs)]},
            {"bufferView": 1, "componentType": 5126, "count": n, "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": n, "type": "VEC2"},
            {"bufferView": 3, "componentType": 5123, "count": len(mesh.indices), "type": "SCALAR"},
        ],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": len(pos), "target": 34962},
            {"buffer": 0, "byteOffset": len(pos), "byteLength": len(nor), "target": 34962},
            {"buffer": 0, "byteOffset": len(pos) + len(nor), "byteLength": len(uv), "target": 34962},
            {"buffer": 0, "byteOffset": len(pos) + len(nor) + len(uv),
             "byteLength": len(mesh.indices) * 2, "target": 34963},
        ],
        "buffers": [{"byteLength": len(blob)}],
    }
    js = pad(json.dumps(doc, separators=(",", ":"), sort_keys=True).encode()).replace(b"\0", b" ")
    total = 12 + 8 + len(js) + 8 + len(blob)
    return (struct.pack("<III", 0x46546C67, 2, total) + struct.pack("<II", len(js), 0x4E4F534A) + js
            + struct.pack("<II", len(blob), 0x004E4942) + blob)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, mesh in (("sun_hat", sun_hat()), ("lanyard", lanyard())):
        (OUT / f"{name}.glb").write_bytes(glb(mesh, name))
        print(f"wrote {OUT / (name + '.glb')} ({mesh.triangles()} triangles)")


if __name__ == "__main__":
    main()
