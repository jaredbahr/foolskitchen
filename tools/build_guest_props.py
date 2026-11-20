"""Build the guest-type pieces: the tourist sun hat and the office lanyard
(#661), the farmer's straw hat and overall bib, the walker's knit beanie and the
forager's basket (#663 #657 #659).

python3 tools/build_guest_props.py
Pure standard-library Python: no Blender, no downloads, no random draws, so a
rebuild writes the same bytes. Writes assets/made/people/<piece>.glb.

Both are chunky flat-shaded low-poly pieces in the Mini Characters style,
coloured only through the characters kit's own colormap.png (every face's UVs
point at one swatch; the image is referenced by relative path, never copied).
Units are the kit's source units (the same ones the courier cap and the head
bone use), glTF Y-up, front toward +Z (the models' front before the pivot turn).

* sun_hat.glb: origin at the middle of the hat's underside. The game lifts it
  to each model's head top and sinks it into the hair (person.gd).
* lanyard.glb: origin at the torso bone's rest position, so it rides the chest
  through every clip. It is a strap in a V, a card, and a white shirt front.
* farm_hat.glb, beanie.glb: origin at the middle of the underside, fitted to
  the head top like the sun hat.
* overall_bib.glb: origin at the torso bone's rest position, like the lanyard.
* basket.glb: origin at the top of the handle; it hangs down -Y
  from there. The game hangs it on the arm bone (person.gd).
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
    "gold_straw": (168, 262),  # golden farm straw (255, 211, 99)
    "straw_shade": (168, 330), # the brim's frayed underside (255, 181, 74)
    "bandana": (264, 300),     # red bandana band (207, 83, 79)
    "denim": (360, 330),       # overall denim (95, 116, 203)
    "denim_dark": (360, 380),  # overall seams and pocket (91, 102, 196)
    "button": (136, 300),      # brass buttons (255, 192, 68)
    "knit": (200, 300),        # beanie knit, warm orange (255, 126, 68)
    "knit_cuff": (296, 360),   # the folded cuff, a deeper red-orange (218, 89, 75)
    "bobble": (8, 300),        # cream bobble (253, 228, 199)
    "wicker": (40, 360),       # basket wicker, light tan (245, 206, 160)
    "wicker_dark": (392, 420), # rim and handle, a warm brown (176, 96, 65)
    "mushroom": (296, 400),    # button mushroom caps, off-white (239, 239, 245)
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


def strut(mesh: Mesh, start, end, width: float, thick: float, swatch: str, up=(0.0, 0.0, 1.0)) -> None:
    """A square-section bar from start to end; `up` picks which way `thick` faces."""
    d = (end[0] - start[0], end[1] - start[1], end[2] - start[2])
    length = math.sqrt(sum(x * x for x in d))
    d = (d[0] / length, d[1] / length, d[2] / length)
    side = (d[1] * up[2] - d[2] * up[1], d[2] * up[0] - d[0] * up[2], d[0] * up[1] - d[1] * up[0])
    sl = math.sqrt(sum(x * x for x in side)) or 1.0
    side = (side[0] / sl, side[1] / sl, side[2] / sl)
    n = (side[1] * d[2] - side[2] * d[1], side[2] * d[0] - side[0] * d[2], side[0] * d[1] - side[1] * d[0])
    w, t = width / 2.0, thick / 2.0
    def corner(e, a, b):
        return (e[0] + a * side[0] * w + b * n[0] * t, e[1] + a * side[1] * w + b * n[1] * t,
                e[2] + a * side[2] * w + b * n[2] * t)
    s = {(a, b): corner(start, a, b) for a in (-1, 1) for b in (-1, 1)}
    e = {(a, b): corner(end, a, b) for a in (-1, 1) for b in (-1, 1)}
    for (a1, b1), (a2, b2) in (((-1, 1), (1, 1)), ((1, 1), (1, -1)), ((1, -1), (-1, -1)), ((-1, -1), (-1, 1))):
        mesh.face([s[a1, b1], s[a2, b2], e[a2, b2], e[a1, b1]], swatch)
    mesh.face([e[-1, 1], e[1, 1], e[1, -1], e[-1, -1]], swatch)
    mesh.face([s[-1, -1], s[1, -1], s[1, 1], s[-1, 1]], swatch)


def farm_hat() -> Mesh:
    """A golden straw farm hat: a wide, ragged brim, a round crown and a red bandana band."""
    mesh = Mesh()
    segments = 14
    # Ragged brim: every other rim point a little shorter, so the edge reads frayed.
    rim = []
    for i in range(segments * 2):
        angle = math.pi * i / segments
        r = 0.245 if i % 2 == 0 else 0.222
        rim.append((r * math.sin(angle), r * math.cos(angle)))
    top = [(x, 0.03, z) for x, z in rim]
    bottom = [(x, 0.0, z) for x, z in rim]
    count = len(rim)
    for i in range(count):
        j = (i + 1) % count
        mesh.face([bottom[i], top[i], top[j], bottom[j]], "straw_shade")
    mesh.face(list(reversed(top)), "gold_straw")
    mesh.face(bottom, "straw_shade")
    # A rounded crown: a short drum and a domed cap, both golden.
    frustum(mesh, (0.0, 0.03, 0.0), 0.16, 0.155, 0.045, "gold_straw", segments=segments, cap_bottom=False)
    frustum(mesh, (0.0, 0.075, 0.0), 0.155, 0.11, 0.035, "gold_straw", segments=segments, cap_bottom=False)
    frustum(mesh, (0.0, 0.03, 0.0), 0.166, 0.162, 0.024, "bandana", segments=segments, cap_bottom=False)
    return mesh


def beanie() -> Mesh:
    """An orange knit beanie: a folded cuff, a rounded crown and a small cream bobble."""
    mesh = Mesh()
    segments = 12
    frustum(mesh, (0.0, 0.0, 0.0), 0.21, 0.205, 0.05, "knit_cuff", segments=segments)
    frustum(mesh, (0.0, 0.05, 0.0), 0.198, 0.17, 0.05, "knit", segments=segments, cap_bottom=False)
    frustum(mesh, (0.0, 0.1, 0.0), 0.17, 0.09, 0.04, "knit", segments=segments, cap_bottom=False)
    # Bobble: a little octagonal ball (two stacked frusta).
    frustum(mesh, (0.0, 0.13, 0.0), 0.035, 0.055, 0.025, "bobble", segments=8)
    frustum(mesh, (0.0, 0.155, 0.0), 0.055, 0.03, 0.03, "bobble", segments=8, cap_bottom=False)
    return mesh


def overall_bib() -> Mesh:
    """A denim bib, two shoulder straps and brass buttons, in torso-bone space."""
    mesh = Mesh()
    ox, oy, oz = TORSO_ORIGIN

    def at(x: float, y: float, z: float):
        return (x - ox, y - oy, z - oz)

    zs = CHEST_Z
    box(mesh, at(0.0, 0.245, zs), (0.15, 0.1, 0.014), "denim")                  # bib
    box(mesh, at(0.0, 0.25, zs + 0.009), (0.06, 0.04, 0.006), "denim_dark")      # pocket
    for sign in (-1.0, 1.0):
        strut(mesh, at(sign * 0.06, 0.29, zs), at(sign * 0.072, 0.35, zs - 0.012), 0.032, 0.012, "denim")
        strut(mesh, at(sign * 0.072, 0.35, zs - 0.012), at(sign * 0.072, 0.358, -0.1), 0.032, 0.012, "denim",
              up=(0.0, 1.0, 0.0))
        box(mesh, at(sign * 0.058, 0.287, zs + 0.01), (0.022, 0.022, 0.008), "button")
    return mesh


def basket() -> Mesh:
    """A small, wide wicker basket with an arched handle and three button mushrooms."""
    mesh = Mesh()
    # Handle: an arch of three bars from rim to rim, its top at the hook point (the origin).
    rim_y = -0.06
    arch = [(-0.1, rim_y), (-0.062, 0.0), (0.062, 0.0), (0.1, rim_y)]
    for a, b in zip(arch, arch[1:]):
        strut(mesh, (a[0], a[1], 0.0), (b[0], b[1], 0.0), 0.024, 0.024, "wicker")
    # Body: a flared tub, narrower at the foot, with a light rim and one dark weave band.
    frustum(mesh, (0.0, rim_y - 0.075, 0.0), 0.09, 0.112, 0.075, "wicker", segments=8)
    frustum(mesh, (0.0, rim_y - 0.016, 0.0), 0.12, 0.12, 0.018, "wicker", segments=8, cap_bottom=False)
    frustum(mesh, (0.0, rim_y - 0.052, 0.0), 0.106, 0.108, 0.012, "wicker_dark", segments=8, cap_bottom=False)
    # The shadowy inside, and the day's finds on top of it.
    frustum(mesh, (0.0, rim_y + 0.002, 0.0), 0.1, 0.1, 0.001, "wicker_dark", segments=8, cap_bottom=False)
    for x, z, r in ((-0.04, 0.018, 0.04), (0.035, -0.026, 0.036), (0.04, 0.038, 0.03)):
        frustum(mesh, (x, rim_y + 0.003, z), r, r * 0.45, 0.026, "mushroom", segments=6, cap_bottom=False)
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
    pieces = (("sun_hat", sun_hat()), ("lanyard", lanyard()), ("farm_hat", farm_hat()), ("beanie", beanie()),
              ("overall_bib", overall_bib()), ("basket", basket()))
    for name, mesh in pieces:
        (OUT / f"{name}.glb").write_bytes(glb(mesh, name))
        print(f"wrote {OUT / (name + '.glb')} ({mesh.triangles()} triangles)")


if __name__ == "__main__":
    main()
