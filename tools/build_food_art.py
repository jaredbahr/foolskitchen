"""Build the made serving pieces for the food art pass (vessels, drinks and the
dishes the Food Kit lacks).

python3 tools/build_food_art.py
Pure standard-library Python: no Blender, no downloads, no random draws, so a
rebuild writes the same bytes. Writes assets/made/food/<piece>.glb and prints
each piece's triangle count (docs/ART_STYLE.md §8: about 300 for a small prop).

Every piece is a chunky, flat-shaded low-poly shape coloured only through the
Food Kit's own colormap.png (each face's UVs point at one swatch; the image is
referenced by relative path, never copied). Units are the Food Kit's source
units: the game scales every food piece by ArtScale.FOOD_SCALE, exactly like
the kit models it sits beside. glTF Y-up; the origin is the middle of the
underside.

Fills (`*_fill`) are authored in their vessel's own space, so they sit inside
the kit bowl, pan or deep plate they name without any further placement.
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "made" / "food"
COLORMAP_URI = "../../kenney/food/Textures/colormap.png"
SIZE = 512.0

# Food Kit colormap texels (x, y), each the flat middle of one kit swatch.
SWATCH = {
    "white": (456, 444),        # plates and cups (255, 255, 255)
    "porcelain": (488, 470),    # shaded porcelain (223, 223, 235)
    "glass": (72, 188),         # pale glass blue (208, 232, 255)
    "blue": (8, 188),           # diner-plate blue (103, 148, 217)
    "blue_dark": (40, 230),     # its darker band (88, 91, 191)
    "purple": (168, 240),       # blueberries (99, 63, 188)
    "salmon": (8, 316),         # shrimp, cooked salmon pink (241, 151, 108)
    "rust": (40, 360),          # crust shadow (181, 101, 69)
    "brown": (72, 316),         # toast crust, gravy (176, 96, 65)
    "tan": (136, 316),          # kraft paper, bread (242, 191, 153)
    "toast": (168, 350),        # toasted top (222, 161, 123)
    "cream": (200, 316),        # milk, foam, crumb (253, 228, 199)
    "wheat": (232, 370),        # paper sleeve (244, 202, 153)
    "green": (264, 316),        # herbs (97, 203, 139)
    "yellow": (328, 316),       # cheese, chips (255, 192, 68)
    "golden": (360, 350),       # batter, crisp chips (255, 181, 74)
    "amber": (360, 380),        # beer (255, 151, 49)
    "orange": (392, 316),       # cereal, shrimp tail (255, 126, 68)
    "red": (456, 316),          # wine, tomato, basket (207, 83, 79)
    "tomato": (488, 350),       # tomato soup (233, 97, 71)
    "coffee": (72, 444),        # coffee, olives (65, 51, 49)
    "grey": (264, 444),         # metal (134, 139, 161)
}


class Mesh:
    def __init__(self) -> None:
        self.positions: list[tuple[float, float, float]] = []
        self.normals: list[tuple[float, float, float]] = []
        self.uvs: list[tuple[float, float]] = []
        self.indices: list[int] = []

    def face(self, points, swatch: str, toward=None) -> None:
        """One flat convex polygon. `toward` (a direction) flips the winding so
        the face normal points that way; otherwise the given winding is kept."""
        points = list(points)
        a, b, c = points[0], points[1], points[2]
        u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        n = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        if toward is not None and n[0] * toward[0] + n[1] * toward[1] + n[2] * toward[2] < 0.0:
            points.reverse()
            n = (-n[0], -n[1], -n[2])
        length = math.sqrt(sum(x * x for x in n)) or 1.0
        n = (n[0] / length, n[1] / length, n[2] / length)
        x, y = SWATCH[swatch]
        uv = ((x + 0.5) / SIZE, (y + 0.5) / SIZE)
        base = len(self.positions)
        for p in points:
            self.positions.append(tuple(round(c, 6) for c in p))
            self.normals.append(n)
            self.uvs.append(uv)
        for i in range(1, len(points) - 1):
            self.indices += [base, base + i, base + i + 1]

    def triangles(self) -> int:
        return len(self.indices) // 3


# ---------------------------------------------------------------- shape helpers

def ring(r: float, y: float, segments: int, sx: float = 1.0, sz: float = 1.0, turn: float = 0.0,
         cx: float = 0.0, cz: float = 0.0):
    return [(cx + r * sx * math.sin(turn + 2.0 * math.pi * i / segments), y,
             cz + r * sz * math.cos(turn + 2.0 * math.pi * i / segments)) for i in range(segments)]


def band(mesh: Mesh, a, b, swatch, outward: float = 1.0, up: float = 0.0, swatches=None) -> None:
    """Quads between two rings of equal length. The normal leans `outward`
    (radially, negative for an inside wall) plus `up`."""
    count = len(a)
    for i in range(count):
        j = (i + 1) % count
        mx = (a[i][0] + a[j][0]) / 2.0
        mz = (a[i][2] + a[j][2]) / 2.0
        cx = sum(p[0] for p in a) / count
        cz = sum(p[2] for p in a) / count
        rx, rz = mx - cx, mz - cz
        rl = math.hypot(rx, rz) or 1.0
        toward = (outward * rx / rl, up, outward * rz / rl)
        mesh.face([a[i], b[i], b[j], a[j]], swatches[i % len(swatches)] if swatches else swatch, toward)


def cap(mesh: Mesh, points, swatch: str, up: float = 1.0) -> None:
    mesh.face(points, swatch, (0.0, up, 0.0))


def frustum(mesh: Mesh, r_bottom: float, r_top: float, y0: float, y1: float, swatch: str,
            segments: int = 10, top: bool = True, bottom: bool = True, sx: float = 1.0, sz: float = 1.0,
            turn: float = 0.0, cx: float = 0.0, cz: float = 0.0, top_swatch: str | None = None,
            swatches=None) -> None:
    rb = ring(r_bottom, y0, segments, sx, sz, turn, cx, cz)
    rt = ring(r_top, y1, segments, sx, sz, turn, cx, cz)
    band(mesh, rb, rt, swatch, 1.0, 0.0, swatches)
    if top:
        cap(mesh, rt, top_swatch or swatch, 1.0)
    if bottom:
        cap(mesh, rb, swatch, -1.0)


def slab(mesh: Mesh, outline, y0: float, y1: float, swatch: str, top_swatch: str | None = None,
         inset: float = 0.0, bevel: float = 0.0, bottom: bool = True) -> None:
    """A flat 2D outline (x, z, convex, any order) extruded from y0 to y1; with
    a bevel the top is inset by `inset` over the last `bevel` of height."""
    cx = sum(p[0] for p in outline) / len(outline)
    cz = sum(p[1] for p in outline) / len(outline)

    def shrink(points, d):
        out = []
        for x, z in points:
            dx, dz = x - cx, z - cz
            dl = math.hypot(dx, dz) or 1.0
            out.append((x - dx / dl * d, z - dz / dl * d))
        return out

    low = [(x, y0, z) for x, z in outline]
    mid_y = y1 - bevel
    mid = [(x, mid_y, z) for x, z in outline]
    band_xz = shrink(outline, inset) if bevel > 0.0 else outline
    high = [(x, y1, z) for x, z in band_xz]
    band(mesh, low, mid, swatch, 1.0, 0.0)
    if bevel > 0.0:
        band(mesh, mid, high, swatch, 1.0, 1.0)
    cap(mesh, high, top_swatch or swatch, 1.0)
    if bottom:
        cap(mesh, low, swatch, -1.0)


def box(mesh: Mesh, centre, size, swatch: str, top_swatch: str | None = None, yaw: float = 0.0,
        tilt: float = 0.0) -> None:
    """A box turned `yaw` about Y, then tipped `tilt` about its own long (x) axis."""
    hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
    cy, sy = math.cos(yaw), math.sin(yaw)
    ct, st = math.cos(tilt), math.sin(tilt)

    def p(ax, ay, az):
        x, y, z = ax * hx, ay * hy, az * hz
        y, z = y * ct - z * st, y * st + z * ct
        return (centre[0] + x * cy + z * sy, centre[1] + y, centre[2] - x * sy + z * cy)

    faces = {
        "+x": [p(1, -1, -1), p(1, 1, -1), p(1, 1, 1), p(1, -1, 1)],
        "-x": [p(-1, -1, 1), p(-1, 1, 1), p(-1, 1, -1), p(-1, -1, -1)],
        "+y": [p(-1, 1, -1), p(-1, 1, 1), p(1, 1, 1), p(1, 1, -1)],
        "-y": [p(-1, -1, 1), p(-1, -1, -1), p(1, -1, -1), p(1, -1, 1)],
        "+z": [p(-1, -1, 1), p(1, -1, 1), p(1, 1, 1), p(-1, 1, 1)],
        "-z": [p(1, -1, -1), p(-1, -1, -1), p(-1, 1, -1), p(1, 1, -1)],
    }
    centre_v = centre
    for key, quad in faces.items():
        mx = sum(q[0] for q in quad) / 4.0 - centre_v[0]
        my = sum(q[1] for q in quad) / 4.0 - centre_v[1]
        mz = sum(q[2] for q in quad) / 4.0 - centre_v[2]
        mesh.face(quad, top_swatch if key == "+y" and top_swatch else swatch, (mx, my, mz))


def strut(mesh: Mesh, start, end, width: float, thick: float, swatch: str) -> None:
    """A square-section bar from start to end."""
    d = (end[0] - start[0], end[1] - start[1], end[2] - start[2])
    length = math.sqrt(sum(x * x for x in d))
    d = (d[0] / length, d[1] / length, d[2] / length)
    up = (0.0, 1.0, 0.0) if abs(d[1]) < 0.9 else (1.0, 0.0, 0.0)
    side = (d[1] * up[2] - d[2] * up[1], d[2] * up[0] - d[0] * up[2], d[0] * up[1] - d[1] * up[0])
    sl = math.sqrt(sum(x * x for x in side)) or 1.0
    side = (side[0] / sl, side[1] / sl, side[2] / sl)
    n = (side[1] * d[2] - side[2] * d[1], side[2] * d[0] - side[0] * d[2], side[0] * d[1] - side[1] * d[0])
    w, t = width / 2.0, thick / 2.0
    mid = ((start[0] + end[0]) / 2.0, (start[1] + end[1]) / 2.0, (start[2] + end[2]) / 2.0)

    def corner(e, a, b):
        return (e[0] + a * side[0] * w + b * n[0] * t, e[1] + a * side[1] * w + b * n[1] * t,
                e[2] + a * side[2] * w + b * n[2] * t)

    s = {(a, b): corner(start, a, b) for a in (-1, 1) for b in (-1, 1)}
    e = {(a, b): corner(end, a, b) for a in (-1, 1) for b in (-1, 1)}
    for (a1, b1), (a2, b2) in (((-1, 1), (1, 1)), ((1, 1), (1, -1)), ((1, -1), (-1, -1)), ((-1, -1), (-1, 1))):
        quad = [s[a1, b1], s[a2, b2], e[a2, b2], e[a1, b1]]
        cx = sum(q[0] for q in quad) / 4.0 - mid[0]
        cy = sum(q[1] for q in quad) / 4.0 - mid[1]
        cz = sum(q[2] for q in quad) / 4.0 - mid[2]
        mesh.face(quad, swatch, (cx, cy, cz))
    mesh.face([e[-1, 1], e[1, 1], e[1, -1], e[-1, -1]], swatch, d)
    mesh.face([s[-1, -1], s[1, -1], s[1, 1], s[-1, 1]], swatch, (-d[0], -d[1], -d[2]))


def dome(mesh: Mesh, rings, swatch: str, segments: int = 10, cx: float = 0.0, cz: float = 0.0,
         turn: float = 0.0, swatches=None, sx: float = 1.0, sz: float = 1.0) -> None:
    """A round heap: (radius, y) rings from the bottom up, closed at the top."""
    loops = [ring(r, y, segments, sx, sz, turn, cx, cz) for r, y in rings]
    for a, b in zip(loops, loops[1:]):
        band(mesh, a, b, swatch, 1.0, 0.6, swatches)
    cap(mesh, loops[-1], (swatches[0] if swatches else swatch), 1.0)


# ---------------------------------------------------------------- vessels

def diner_plate() -> Mesh:
    """The kit `plate` profile (same radius, rim and well) in diner blue, so a
    white egg reads on it: a white rim edge around a blue well, white underside."""
    m = Mesh()
    seg = 12
    foot = ring(0.25, 0.0, seg)
    foot_top = ring(0.27, 0.02, seg)
    under = ring(0.446, 0.07, seg)
    edge = ring(0.446, 0.09, seg)
    rim_in = ring(0.30, 0.09, seg)
    well = ring(0.258, 0.05, seg)
    cap(m, foot, "white", -1.0)
    band(m, foot, foot_top, "white", 1.0, -0.5)
    band(m, foot_top, under, "white", 1.0, -1.0)
    band(m, under, edge, "white", 1.0, 0.0)
    band(m, edge, rim_in, "glass", 0.0, 1.0)
    band(m, rim_in, well, "blue", -1.0, 1.0)
    cap(m, well, "blue", 1.0)
    return m


def coaster() -> Mesh:
    """A round card beer mat with a red printed ring."""
    m = Mesh()
    frustum(m, 0.2, 0.2, 0.0, 0.012, "tan", segments=12)
    frustum(m, 0.15, 0.15, 0.012, 0.016, "red", segments=12, bottom=False)
    frustum(m, 0.12, 0.12, 0.016, 0.018, "tan", segments=12, bottom=False)
    return m


def paper_tray() -> Mesh:
    """A paper boat tray: four splayed low walls printed red with a white top
    band, and a white paper floor. Food sits on its floor (y 0.012)."""
    m = Mesh()
    lo = [(-0.24, 0.0, -0.15), (0.24, 0.0, -0.15), (0.24, 0.0, 0.15), (-0.24, 0.0, 0.15)]
    hi = [(-0.29, 0.1, -0.19), (0.29, 0.1, -0.19), (0.29, 0.1, 0.19), (-0.29, 0.1, 0.19)]
    mid = [(-0.275, 0.07, -0.178), (0.275, 0.07, -0.178), (0.275, 0.07, 0.178), (-0.275, 0.07, 0.178)]
    t = 0.012
    lo_in = [(x * 0.95, 0.012, z * 0.92) for x, _, z in lo]
    hi_in = [(x - math.copysign(t, x), 0.1, z - math.copysign(t, z)) for x, _, z in hi]
    cap(m, lo, "tan", -1.0)
    band(m, lo, mid, "red", 1.0, -0.2)
    band(m, mid, hi, "white", 1.0, -0.2)
    band(m, hi, hi_in, "white", 0.0, 1.0)
    band(m, hi_in, lo_in, "red", -1.0, 0.3)
    cap(m, lo_in, "white", 1.0)
    return m


def fry_basket() -> Mesh:
    """A woven wicker bar basket, oval, lined with white paper."""
    m = Mesh()
    seg = 10
    sx, sz = 1.18, 0.86
    base = ring(0.26, 0.0, seg, sx, sz)
    top = ring(0.36, 0.12, seg, sx, sz)
    top_in = ring(0.33, 0.12, seg, sx, sz)
    floor = ring(0.24, 0.025, seg, sx, sz)
    cap(m, base, "brown", -1.0)
    band(m, base, top, "brown", 1.0, -0.3, swatches=["brown", "rust"])
    band(m, top, top_in, "tan", 0.0, 1.0)
    band(m, top_in, floor, "rust", -1.0, 0.3)
    cap(m, floor, "white", 1.0)
    # The paper liner's corners fold up over the inner wall at the four ends.
    for angle in (0.6, math.pi - 0.6, math.pi + 0.6, -0.6):
        cx, cz = 0.3 * sx * math.sin(angle), 0.3 * sz * math.cos(angle)
        ix, iz = 0.16 * sx * math.sin(angle), 0.16 * sz * math.cos(angle)
        tx, tz = -math.cos(angle) * 0.07, math.sin(angle) * 0.07
        m.face([(ix - tx, 0.03, iz - tz), (ix + tx, 0.03, iz + tz), (cx, 0.135, cz)], "white", (0.0, 1.0, 0.0))
    return m


# ---------------------------------------------------------------- drinks

def beer_glass() -> Mesh:
    """A pint of amber beer with a white head of foam, in a pale glass foot."""
    m = Mesh()
    seg = 10
    frustum(m, 0.1, 0.104, 0.0, 0.035, "glass", segments=seg)
    frustum(m, 0.104, 0.122, 0.035, 0.27, "amber", segments=seg, top=False, bottom=False)
    frustum(m, 0.122, 0.128, 0.27, 0.33, "cream", segments=seg, top=False, bottom=False)
    dome(m, [(0.128, 0.33), (0.11, 0.355), (0.06, 0.37)], "white", segments=seg)
    return m


def wine_glass() -> Mesh:
    """A stemmed glass of red wine: pale glass foot, stem and rim, red wine in
    the bowl (the kit's glass-wine maps half its vertices to the colormap's
    black corner, so it renders black)."""
    m = Mesh()
    seg = 10
    frustum(m, 0.1, 0.085, 0.0, 0.016, "glass", segments=seg)
    frustum(m, 0.018, 0.018, 0.016, 0.17, "glass", segments=6, top=False, bottom=False)
    frustum(m, 0.03, 0.1, 0.16, 0.22, "red", segments=seg, top=False, bottom=True)
    frustum(m, 0.1, 0.112, 0.22, 0.29, "red", segments=seg, top=True, bottom=False)
    frustum(m, 0.112, 0.1, 0.29, 0.37, "glass", segments=seg, top=False, bottom=False)
    return m


def coffee_to_go() -> Mesh:
    """A white paper cup with a kraft sleeve and a white lid: the takeaway cup."""
    m = Mesh()
    seg = 10
    frustum(m, 0.085, 0.1, 0.0, 0.1, "white", segments=seg, top=False)
    frustum(m, 0.103, 0.113, 0.1, 0.2, "wheat", segments=seg, top=False, bottom=False)
    frustum(m, 0.111, 0.117, 0.2, 0.27, "white", segments=seg, top=False, bottom=False)
    frustum(m, 0.122, 0.122, 0.27, 0.3, "porcelain", segments=seg, top=False)
    frustum(m, 0.1, 0.09, 0.3, 0.325, "white", segments=seg, bottom=False)
    box(m, (0.0, 0.33, 0.07), (0.04, 0.012, 0.02), "coffee")
    return m


# ---------------------------------------------------------------- dishes

def battered_fish() -> Mesh:
    """A golden battered fillet: a thick, tapering slab with a bevelled top."""
    m = Mesh()
    body = [(-0.3, 0.0), (-0.24, 0.085), (-0.06, 0.12), (0.14, 0.1), (0.27, 0.05), (0.3, 0.0),
            (0.27, -0.05), (0.14, -0.1), (-0.06, -0.12), (-0.24, -0.085)]
    slab(m, body, 0.0, 0.085, "rust", top_swatch="golden", inset=0.035, bevel=0.04)
    # The tail, battered too, and crunchy batter bumps along the top.
    slab(m, [(-0.27, 0.0), (-0.4, 0.11), (-0.4, -0.11)], 0.0, 0.05, "rust", top_swatch="golden")
    for x, z in ((-0.15, 0.02), (0.0, -0.03), (0.12, 0.02)):
        frustum(m, 0.04, 0.025, 0.08, 0.1, "golden", segments=6, cx=x, cz=z, top_swatch="toast", bottom=False)
    return m


CHIPS = (
    # (x, z, yaw, y, tilt) : a deterministic heap, two layers
    (-0.1, -0.05, 0.3, 0.02, 0.0), (0.0, -0.08, -0.4, 0.02, 0.0), (0.1, -0.04, 0.9, 0.02, 0.0),
    (-0.08, 0.06, -0.9, 0.02, 0.0), (0.04, 0.07, 0.2, 0.02, 0.0), (0.12, 0.05, -0.2, 0.02, 0.0),
    (-0.13, 0.0, 1.4, 0.02, 0.0), (0.0, 0.0, 1.1, 0.02, 0.0),
    (-0.05, -0.02, 0.7, 0.06, 0.25), (0.06, 0.0, -0.6, 0.06, -0.25), (0.0, 0.04, 0.05, 0.065, 0.2),
    (-0.03, 0.03, -1.3, 0.1, 0.0), (0.03, -0.03, 1.6, 0.095, 0.0),
)


def chips_pile() -> Mesh:
    """A heap of thick-cut chips, golden with paler ends."""
    m = Mesh()
    for x, z, yaw, y, tilt in CHIPS:
        box(m, (x, y, z), (0.2, 0.04, 0.04), "yellow", top_swatch="golden", yaw=yaw, tilt=tilt)
    return m


def soup_fill(swatch: str = "tomato") -> Mesh:
    """Tomato soup for the kit `bowl` (its well, rim at 0.214) standing on the
    kit `plate` well (0.05): a red-orange surface, a cream swirl and herbs."""
    m = Mesh()
    lift = 0.05
    frustum(m, 0.205, 0.234, lift + 0.064, lift + 0.18, swatch, segments=8, turn=math.pi / 8)
    dome(m, [(0.08, lift + 0.18), (0.055, lift + 0.195), (0.02, lift + 0.2)], "cream", segments=8, cx=0.03, cz=-0.02)
    for x, z, yaw in ((-0.1, 0.06, 0.4), (0.1, 0.09, -0.7), (-0.05, -0.11, 1.2), (0.12, -0.06, 0.2)):
        box(m, (x, lift + 0.185, z), (0.035, 0.012, 0.022), "green", yaw=yaw)
    return m


def cereal_fill() -> Mesh:
    """Milk and orange cereal loops for the kit `bowl` (well 0.064 to rim 0.214)."""
    m = Mesh()
    frustum(m, 0.205, 0.232, 0.064, 0.178, "cream", segments=8, turn=math.pi / 8)
    loops = ((-0.12, 0.04), (-0.05, -0.12), (0.06, -0.08), (0.13, 0.03), (0.02, 0.12), (-0.06, 0.03),
             (0.05, 0.02), (-0.13, -0.06), (0.1, 0.11), (-0.03, -0.03), (0.12, -0.12))
    for index, (x, z) in enumerate(loops):
        frustum(m, 0.032, 0.03, 0.172, 0.192, "orange" if index % 3 else "yellow", segments=6, cx=x, cz=z,
                bottom=False, turn=index * 0.4)
    return m


def stew_fill() -> Mesh:
    """Seafood stew for the kit `pan` (floor 0.052, rim 0.154): a rich red
    broth with potato and fish chunks and green herbs."""
    m = Mesh()
    frustum(m, 0.19, 0.27, 0.052, 0.13, "red", segments=10, top_swatch="tomato")
    for x, z, s, sw in ((-0.12, 0.05, 0.07, "cream"), (0.05, 0.13, 0.06, "yellow"), (0.13, -0.06, 0.065, "cream"),
                        (-0.04, -0.14, 0.06, "yellow"), (0.0, 0.0, 0.055, "cream")):
        box(m, (x, 0.135, z), (s, 0.04, s), sw, yaw=x * 7.0)
    for x, z in ((-0.16, -0.06), (0.08, -0.15), (0.16, 0.1), (-0.07, 0.17)):
        box(m, (x, 0.132, z), (0.035, 0.01, 0.02), "green", yaw=z * 9.0)
    return m


def broth_fill() -> Mesh:
    """A shallow golden broth for the kit `plate-deep` (well 0.055, rim 0.145)."""
    m = Mesh()
    frustum(m, 0.25, 0.33, 0.05, 0.1, "golden", segments=12, top_swatch="yellow")
    for x, z in ((-0.2, 0.08), (0.18, 0.14), (0.05, -0.24), (-0.08, -0.18), (0.24, -0.05)):
        box(m, (x, 0.102, z), (0.04, 0.012, 0.024), "green", yaw=x * 9.0)
    return m


def shrimp(m: Mesh, x: float, y: float, z: float, yaw: float, size: float = 1.0) -> None:
    """One curled, pink-orange shrimp: a C of three tapering segments and a red tail."""
    cy, sy = math.cos(yaw), math.sin(yaw)

    def at(px, py, pz):
        return (x + (px * cy + pz * sy) * size, y + py * size, z + (-px * sy + pz * cy) * size)

    arc = [(0.0, 0.0, -0.06), (0.05, 0.03, -0.035), (0.065, 0.045, 0.01), (0.04, 0.04, 0.055)]
    widths = (0.06, 0.055, 0.045)
    for (a, b, w) in zip(arc, arc[1:], widths):
        strut(m, at(*a), at(*b), w * size, w * size * 0.9, "salmon")
    tail = arc[-1]
    m.face([at(tail[0], tail[1], tail[2]), at(tail[0] - 0.05, tail[1] + 0.005, tail[2] + 0.04),
            at(tail[0] + 0.02, tail[1] + 0.005, tail[2] + 0.06)], "orange", (0.0, 1.0, 0.0))


def shrimp_skewer() -> Mesh:
    """Four curled shrimp threaded on a wooden skewer."""
    m = Mesh()
    strut(m, (-0.34, 0.04, 0.0), (0.34, 0.04, 0.0), 0.018, 0.018, "wheat")
    for index, x in enumerate((-0.21, -0.07, 0.07, 0.21)):
        shrimp(m, x, 0.012, 0.0, math.pi / 2.0 + (0.25 if index % 2 else -0.25), 1.3)
    return m


def stew_shrimp() -> Mesh:
    """Two shrimp resting on a stew or broth."""
    m = Mesh()
    shrimp(m, -0.04, 0.0, 0.02, 0.6, 1.1)
    shrimp(m, 0.08, 0.0, -0.05, 2.4, 1.0)
    return m


def toast_half(m: Mesh, cx: float, cz: float, yaw: float, base: float = 0.0) -> None:
    """A diagonal half of a grilled cheese: two golden slices with a thick
    layer of cheese oozing out past the crust and down the cut edge."""
    cy, sy = math.cos(yaw), math.sin(yaw)
    tri = [(-0.17, -0.15), (0.19, -0.15), (-0.17, 0.2)]

    def place(points, grow=1.0):
        return [(cx + (x * grow) * cy + (z * grow) * sy, cz - (x * grow) * sy + (z * grow) * cy) for x, z in points]

    slab(m, place(tri), base, base + 0.055, "toast", top_swatch="tan")
    slab(m, place(tri, 1.12), base + 0.055, base + 0.09, "yellow", bottom=False)
    hx, hz = (tri[1][0] + tri[2][0]) / 2.0 + 0.02, (tri[1][1] + tri[2][1]) / 2.0 + 0.02
    box(m, (cx + hx * cy + hz * sy, base + 0.055, cz - hx * sy + hz * cy), (0.09, 0.07, 0.035), "yellow", yaw=yaw + 0.79)
    slab(m, place(tri), base + 0.09, base + 0.145, "toast", top_swatch="tan", inset=0.02, bevel=0.02)


def grilled_cheese() -> Mesh:
    """Two grilled-cheese halves, one propped on the other so the cut edge
    and its cheese face the room."""
    m = Mesh()
    toast_half(m, -0.03, 0.02, 0.0)
    toast_half(m, 0.06, -0.03, math.pi + 0.5, 0.145)
    return m


def melted_cheese() -> Mesh:
    """A melted cheese sheet sized for the kit `bread` slice (0.44 x 0.37)."""
    m = Mesh()
    outline = [(-0.19, -0.13), (0.15, -0.15), (0.2, -0.05), (0.19, 0.1), (0.12, 0.155), (-0.17, 0.14),
               (-0.205, 0.0)]
    slab(m, outline, 0.0, 0.02, "yellow", top_swatch="yellow")
    return m


CLUB_LAYERS = (("brown", "toast", 0.04), ("green", "green", 0.02), ("red", "red", 0.02), ("brown", "toast", 0.04),
               ("salmon", "salmon", 0.025), ("cream", "yellow", 0.015), ("brown", "toast", 0.04))


def club_wedge() -> Mesh:
    """A quarter of a toasted club sandwich: three slices of toast layered with
    lettuce, tomato, ham and cheese, the fillings a touch wider than the bread."""
    m = Mesh()
    tri = [(-0.13, -0.12), (0.17, -0.12), (-0.13, 0.18)]
    y = 0.0
    for side, top, height in CLUB_LAYERS:
        grow = 1.06 if side != "brown" else 1.0
        slab(m, [(x * grow, z * grow) for x, z in tri], y, y + height, side, top_swatch=top)
        y += height
    return m


def club_pick() -> Mesh:
    """A cocktail pick with a green olive and a red frill: holds a club sandwich."""
    m = Mesh()
    strut(m, (0.0, 0.0, 0.0), (0.0, 0.2, 0.0), 0.016, 0.016, "wheat")
    frustum(m, 0.03, 0.03, 0.17, 0.215, "green", segments=6)
    frustum(m, 0.028, 0.012, 0.215, 0.25, "red", segments=6, bottom=False)
    return m


def muffin() -> Mesh:
    """A blueberry muffin: a pleated paper case and a domed, golden top that
    overhangs it, dotted with blueberries."""
    m = Mesh()
    seg = 12
    frustum(m, 0.115, 0.15, 0.0, 0.15, "white", segments=seg, top=False, swatches=["white", "glass"])
    dome(m, [(0.145, 0.145), (0.168, 0.165), (0.16, 0.21), (0.12, 0.25), (0.05, 0.27)], "toast", segments=seg)
    berries = ((0.07, 0.24, 0.04), (-0.06, 0.245, 0.06), (0.0, 0.26, -0.06), (-0.1, 0.215, -0.07),
               (0.12, 0.205, -0.06), (0.03, 0.275, 0.0))
    for x, y, z in berries:
        box(m, (x, y, z), (0.04, 0.035, 0.04), "purple", yaw=x * 10.0)
    return m


def savory_pie() -> Mesh:
    """A small individual savoury pie: a crimped golden crust, a domed brown
    lid with steam slits, gravy showing at one vent."""
    m = Mesh()
    seg = 12
    frustum(m, 0.2, 0.24, 0.0, 0.1, "rust", segments=seg, top=False)
    # Crimped rim: a pale pastry ring, its teeth alternating light and golden.
    rim_low = ring(0.24, 0.1, seg * 2)
    rim_out = ring(0.285, 0.13, seg * 2)
    rim_in = ring(0.23, 0.14, seg * 2)
    band(m, rim_low, rim_out, "toast", 1.0, 0.5, swatches=["toast", "tan"])
    band(m, rim_out, rim_in, "tan", 0.0, 1.0, swatches=["tan", "cream"])
    lid = [(0.23, 0.14), (0.18, 0.18), (0.1, 0.205), (0.03, 0.212)]
    dome(m, lid, "golden", segments=seg)
    # Steam slits cut in the lid, and a pastry leaf on top.
    for yaw in (0.3, 1.87, 3.44, 5.01):
        box(m, (0.13 * math.sin(yaw), 0.19, 0.13 * math.cos(yaw)), (0.022, 0.02, 0.08), "brown", yaw=yaw)
    slab(m, [(-0.07, 0.0), (0.0, -0.035), (0.07, 0.0), (0.0, 0.035)], 0.205, 0.225, "toast", top_swatch="tan")
    return m


# ---------------------------------------------------------------- export

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
        "asset": {"version": "2.0", "generator": "tools/build_food_art.py"},
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


PIECES = (
    ("diner_plate", diner_plate), ("coaster", coaster), ("paper_tray", paper_tray), ("fry_basket", fry_basket),
    ("beer_glass", beer_glass), ("wine_glass", wine_glass), ("coffee_to_go", coffee_to_go),
    ("battered_fish", battered_fish), ("chips_pile", chips_pile), ("tomato_soup_fill", soup_fill),
    ("cereal_fill", cereal_fill), ("stew_fill", stew_fill), ("broth_fill", broth_fill),
    ("shrimp_skewer", shrimp_skewer), ("stew_shrimp", stew_shrimp), ("grilled_cheese", grilled_cheese),
    ("melted_cheese", melted_cheese), ("club_wedge", club_wedge), ("club_pick", club_pick), ("muffin", muffin), ("savory_pie", savory_pie),
)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, build in PIECES:
        mesh = build()
        (OUT / f"{name}.glb").write_bytes(glb(mesh, name))
        print(f"{name}: {mesh.triangles()} triangles")


if __name__ == "__main__":
    main()
