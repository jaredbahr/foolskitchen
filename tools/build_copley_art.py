"""Build Chef Copley's art (#701): his food truck, his gaudy shop sign and the
"Copley's Closing Sign" trophy (the same sign with a CLOSED board hung across it).

python3 tools/build_copley_art.py
Pure standard-library Python: no Blender, no downloads, no random draws, so a
rebuild writes the same bytes. Writes assets/made/copley/copley_truck.glb,
copley_sign.glb, copley_closing_sign.glb and copley.metrics.json.

Style (docs/ART_STYLE.md section 8): chunky flat-shaded boxes and short cylinders,
coloured only through the Mini Characters kit's own colormap.png (every face's UVs
point at one swatch; the image is referenced by relative path, never copied), so
no new texture and no new palette. Copley's colours are the kit's gold and purple,
with the kit red, cream and ink.

Units: every size below is a world size in metres; it is divided once by the shared
furniture scale (src/world/art_scale.gd) when written, so the game's uniform scale
gives it back. glTF Y-up, front toward -Z (the kit rule). Origins:
* copley_truck: the middle of the truck's footprint on the ground. The serving hatch
  and the blank name panel are on the -Z side; the cab is at +X.
* copley_sign and copley_closing_sign: the middle of the frame's bottom edge on its
  back plane (z = 0), so the sign hangs on a wall at z = 0 and its face looks to -Z.
  The too-tall toque rises above the frame on purpose.

The name is never modelled: the game draws it as a Label3D on the blank panel, at
the area recorded in copley.metrics.json ("text").
"""
from __future__ import annotations

import json
import math
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "made" / "copley"
COLORMAP_URI = "../../kenney/characters/Textures/colormap.png"
SIZE = 512.0
FURNITURE_SCALE = float(re.search(r"const FURNITURE_SCALE: float = ([\d.]+)",
                                  (ROOT / "src/world/art_scale.gd").read_text()).group(1))
BUDGET = 800

# Colormap texels (x, y), the nearest kit swatch to each colour named.
SWATCH = {
    "purple": (484, 324),       # (126, 86, 206)
    "purple_dark": (484, 380),  # (92, 57, 184)
    "gold": (132, 260),         # (255, 192, 68)
    "gold_light": (164, 260),   # (255, 211, 99)
    "gold_deep": (164, 348),    # (255, 166, 61)
    "white": (292, 388),        # (252, 252, 253)
    "cream": (4, 260),          # (253, 228, 199)
    "gray": (292, 428),         # (230, 230, 239)
    "ink": (164, 500),          # (59, 62, 74)
    "red": (260, 260),          # (207, 83, 79)
    "sky": (388, 260),          # (208, 232, 255)
    "skin": (36, 332),          # (248, 212, 170)
    "skin_dark": (356, 388),    # (239, 149, 106)
    "brown": (420, 508),        # (132, 84, 66)
}

Vec = tuple[float, float, float]


def sub(a: Vec, b: Vec) -> Vec:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def dot(a: Vec, b: Vec) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def mean(points: list[Vec]) -> Vec:
    n = len(points)
    return (sum(p[0] for p in points) / n, sum(p[1] for p in points) / n, sum(p[2] for p in points) / n)


class Mesh:
    def __init__(self) -> None:
        self.positions: list[Vec] = []
        self.normals: list[Vec] = []
        self.uvs: list[tuple[float, float]] = []
        self.indices: list[int] = []
        # A tilt about the z axis, (pivot x, pivot y, angle): hung boards swing a little.
        self.tilt: tuple[float, float, float] | None = None
        # Everything is authored as the viewer sees it (+x to the viewer's right), but a model's front
        # looks toward -z, where +x is the viewer's left; writing flips x so the finished piece reads true.
        self.flip_x = True

    def _turn(self, p: Vec) -> Vec:
        if self.tilt is None:
            return p
        px, py, angle = self.tilt
        c, s = math.cos(angle), math.sin(angle)
        x, y = p[0] - px, p[1] - py
        return (px + x * c - y * s, py + x * s + y * c, p[2])

    def _turn_dir(self, d: Vec) -> Vec:
        if self.tilt is None:
            return d
        c, s = math.cos(self.tilt[2]), math.sin(self.tilt[2])
        return (d[0] * c - d[1] * s, d[0] * s + d[1] * c, d[2])

    def face(self, points: list[Vec], swatch: str, hint: Vec) -> None:
        """One flat convex polygon; its winding is flipped to face along `hint`."""
        pts = [self._turn(p) for p in points]
        hint = self._turn_dir(hint)
        if self.flip_x:
            pts = [(-p[0], p[1], p[2]) for p in pts]
            hint = (-hint[0], hint[1], hint[2])
        n = cross(sub(pts[1], pts[0]), sub(pts[2], pts[0]))
        if dot(n, hint) < 0:
            pts.reverse()
            n = (-n[0], -n[1], -n[2])
        length = math.sqrt(dot(n, n)) or 1.0
        n = (n[0] / length, n[1] / length, n[2] / length)
        x, y = SWATCH[swatch]
        uv = ((x + 0.5) / SIZE, (y + 0.5) / SIZE)
        base = len(self.positions)
        for p in pts:
            self.positions.append(p)
            self.normals.append(n)
            self.uvs.append(uv)
        for i in range(1, len(pts) - 1):
            self.indices += [base, base + i, base + i + 1]

    def triangles(self) -> int:
        return len(self.indices) // 3


def box(m: Mesh, lo: Vec, hi: Vec, swatch: str) -> None:
    x0, y0, z0 = lo
    x1, y1, z1 = hi
    m.face([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], swatch, (0, 0, 1))
    m.face([(x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)], swatch, (0, 0, -1))
    m.face([(x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)], swatch, (1, 0, 0))
    m.face([(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)], swatch, (-1, 0, 0))
    m.face([(x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)], swatch, (0, 1, 0))
    m.face([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], swatch, (0, -1, 0))


def centred_box(m: Mesh, centre: Vec, size: Vec, swatch: str) -> None:
    box(m, (centre[0] - size[0] / 2, centre[1] - size[1] / 2, centre[2] - size[2] / 2),
        (centre[0] + size[0] / 2, centre[1] + size[1] / 2, centre[2] + size[2] / 2), swatch)


def ring_prism(m: Mesh, bottom: list[Vec], top: list[Vec], swatch: str) -> None:
    """A convex prism or frustum between two same-size rings: sides and both caps."""
    n = len(bottom)
    centre = mean(bottom + top)
    for i in range(n):
        j = (i + 1) % n
        quad = [bottom[i], bottom[j], top[j], top[i]]
        m.face(quad, swatch, sub(mean(quad), centre))
    m.face(top, swatch, sub(mean(top), centre))
    m.face(bottom, swatch, sub(mean(bottom), centre))


def zdisc(m: Mesh, cx: float, cy: float, rx: float, ry: float, z0: float, z1: float, swatch: str,
          sides: int = 10) -> None:
    """A short round plate with its axis along z, from z0 to z1."""
    back = [(cx + rx * math.cos(2 * math.pi * i / sides), cy + ry * math.sin(2 * math.pi * i / sides), z0)
            for i in range(sides)]
    front = [(x, y, z1) for x, y, _ in back]
    ring_prism(m, back, front, swatch)


def lathe(m: Mesh, centre: Vec, profile: list[tuple[float, float]], rz: float, swatch: str, sides: int = 10) -> None:
    """A turned shape around a vertical axis: `profile` is (radius, height above centre) from the
    bottom up; the depth is each radius times `rz` (a flat, sign-like hat). Top and bottom are capped."""
    cx, cy, cz = centre
    rings = []
    for r, h in profile:
        rings.append([(cx + r * math.cos(2 * math.pi * i / sides), cy + h, cz + r * rz * math.sin(2 * math.pi * i / sides))
                      for i in range(sides)])
    for row in range(len(rings) - 1):
        for i in range(sides):
            j = (i + 1) % sides
            quad = [rings[row][i], rings[row][j], rings[row + 1][j], rings[row + 1][i]]
            mid = mean(quad)
            m.face(quad, swatch, (mid[0] - cx, 0.0, mid[2] - cz))
    m.face(rings[-1], swatch, (0, 1, 0))
    m.face(list(rings[0]), swatch, (0, -1, 0))


def bar(m: Mesh, a: tuple[float, float], b: tuple[float, float], width: float, z0: float, z1: float, swatch: str) -> None:
    """A strip in the xy plane from a to b, `width` across, from z0 to z1."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)
    nx, ny = -dy / length * width / 2, dx / length * width / 2
    quad = [(a[0] + nx, a[1] + ny), (a[0] - nx, a[1] - ny), (b[0] - nx, b[1] - ny), (b[0] + nx, b[1] + ny)]
    ring_prism(m, [(x, y, z0) for x, y in quad], [(x, y, z1) for x, y in quad], swatch)


def diamond(m: Mesh, centre: Vec, r: float, swatch: str) -> None:
    """A small eight-sided gem (an octahedron): a marquee bulb."""
    cx, cy, cz = centre
    top, bottom = (cx, cy + r, cz), (cx, cy - r, cz)
    ring = [(cx + r, cy, cz), (cx, cy, cz - r), (cx - r, cy, cz), (cx, cy, cz + r)]
    for i in range(4):
        j = (i + 1) % 4
        up = [ring[i], ring[j], top]
        down = [ring[j], ring[i], bottom]
        m.face(up, swatch, sub(mean(up), centre))
        m.face(down, swatch, sub(mean(down), centre))


def front_quad(m: Mesh, x0: float, y0: float, x1: float, y1: float, z: float, swatch: str) -> None:
    m.face([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], swatch, (0, 0, -1))


# Block letters as unit rectangles (u, v from 0 to 1) that never overlap, so no face fights another.
LETTERS = {
    "C": [(0, 0, .27, 1), (.27, .78, 1, 1), (.27, 0, 1, .22)],
    "L": [(0, 0, .28, 1), (.28, 0, 1, .22)],
    "O": [(0, 0, .27, 1), (.73, 0, 1, 1), (.27, .78, .73, 1), (.27, 0, .73, .22)],
    "S": [(0, .78, 1, 1), (0, .61, .27, .78), (0, .39, 1, .61), (.73, .22, 1, .39), (0, 0, 1, .22)],
    "E": [(0, 0, .27, 1), (.27, .78, 1, 1), (.27, .39, .85, .61), (.27, 0, 1, .22)],
    "D": [(0, 0, .27, 1), (.27, .78, .68, 1), (.27, 0, .68, .22), (.68, .12, 1, .88)],
}


# ---------------------------------------------------------------- the sign

# World metres, x centred, y up from the frame's bottom, z = 0 the back plane, front at -z.
SIGN_W, SIGN_H = 0.96, 0.50
FACE = (-0.255, 0.25)                    # the medallion's centre (x, y)
PLATE = (-0.10, 0.10, 0.41, 0.40)        # the name plate: x0, y0, x1, y1
PLATE_FRONT = -0.040
TEXT_AREA = {"centre": [0.155, 0.25, PLATE_FRONT - 0.0015], "size": [0.46, 0.22]}


def add_sign(m: Mesh) -> None:
    hw = SIGN_W / 2
    # Gold frame, purple backing.
    box(m, (-hw, 0.0, -0.05), (hw, 0.04, 0.0), "gold")
    box(m, (-hw, SIGN_H - 0.04, -0.05), (hw, SIGN_H, 0.0), "gold")
    box(m, (-hw, 0.04, -0.05), (-hw + 0.04, SIGN_H - 0.04, 0.0), "gold")
    box(m, (hw - 0.04, 0.04, -0.05), (hw, SIGN_H - 0.04, 0.0), "gold")
    box(m, (-hw + 0.04, 0.04, -0.03), (hw - 0.04, SIGN_H - 0.04, 0.0), "purple_dark")
    # The name plate: a gold border round a cream board.
    x0, y0, x1, y1 = PLATE
    box(m, (x0 - 0.02, y0 - 0.02, -0.034), (x1 + 0.02, y1 + 0.02, -0.030), "gold")
    box(m, (x0, y0, PLATE_FRONT), (x1, y1, -0.034), "cream")
    # Marquee bulbs along the frame, a gap where the toque rises.
    fx, fy = FACE
    for index in range(10):
        x = -0.40 + 0.09 * index
        swatch = "white" if index % 2 == 0 else "gold_light"
        if abs(x - fx) > 0.11:
            diamond(m, (x, SIGN_H - 0.02, -0.058), 0.017, swatch)
        diamond(m, (x, 0.02, -0.058), 0.017, swatch)
    # Copley: a gold medallion, a round smug face, a too-tall toque, an enormous mustache.
    zdisc(m, fx, fy, 0.165, 0.165, -0.034, -0.040, "red", sides=12)
    zdisc(m, fx, fy, 0.118, 0.118, -0.040, -0.050, "skin", sides=12)
    box(m, (fx - 0.092, fy + 0.095, -0.052), (fx + 0.092, fy + 0.135, -0.040), "gold")
    lathe(m, (fx, fy + 0.135, -0.046), [(0.085, 0.0), (0.095, 0.05), (0.122, 0.095), (0.14, 0.155),
                                        (0.128, 0.21), (0.09, 0.245)], 0.2, "white")
    for side in (-1.0, 1.0):
        ex = fx + side * 0.043
        centred_box(m, (ex, fy + 0.034, -0.0505), (0.034, 0.024, 0.002), "white")
        centred_box(m, (ex + 0.004, fy + 0.030, -0.0515), (0.014, 0.016, 0.002), "ink")
        centred_box(m, (ex, fy + 0.047, -0.0525), (0.04, 0.012, 0.002), "skin_dark")     # a heavy lid: smug
    bar(m, (fx - 0.075, fy + 0.066), (fx - 0.018, fy + 0.066), 0.011, -0.0505, -0.0525, "brown")
    bar(m, (fx + 0.018, fy + 0.066), (fx + 0.078, fy + 0.088), 0.011, -0.0505, -0.0525, "brown")  # one brow up
    centred_box(m, (fx, fy - 0.004, -0.0535), (0.034, 0.04, 0.007), "skin_dark")
    centred_box(m, (fx, fy - 0.03, -0.0585), (0.06, 0.04, 0.012), "brown")                         # the bridge
    path = [(0.02, -0.03), (0.10, -0.048), (0.165, -0.02), (0.178, 0.022)]
    widths = [0.046, 0.042, 0.032]
    for side in (-1.0, 1.0):
        for k in range(3):
            a = (fx + side * path[k][0], fy + path[k][1])
            b = (fx + side * path[k + 1][0], fy + path[k + 1][1])
            bar(m, a, b, widths[k], -0.0505, -0.0605, "brown")
    bar(m, (fx + 0.012, fy - 0.088), (fx + 0.05, fy - 0.080), 0.008, -0.0505, -0.0525, "ink")        # a smirk


def add_closed_board(m: Mesh) -> None:
    """The CLOSED board: a red board hung from two cords across the right of the sign, a little tilted."""
    cx, cy = 0.20, 0.19
    half_w, half_h = 0.31, 0.12
    angle = math.radians(-7.0)
    front = -0.062
    c, s = math.cos(angle), math.sin(angle)
    # The cords run from the sign's top bar to the board's top corners.
    for side in (-1.0, 1.0):
        top = (cx + side * 0.25, SIGN_H - 0.02)
        corner = (cx + side * 0.25 * c - (half_h * 0.9) * s, cy + side * 0.25 * s + (half_h * 0.9) * c)
        bar(m, top, corner, 0.008, front - 0.012, front, "ink")
        centred_box(m, (top[0], top[1], front + 0.004), (0.026, 0.026, 0.012), "gold_deep")
    m.tilt = (cx, cy, angle)
    box(m, (cx - half_w - 0.016, cy - half_h - 0.016, front - 0.016), (cx + half_w + 0.016, cy + half_h + 0.016, front), "white")
    box(m, (cx - half_w, cy - half_h, front - 0.026), (cx + half_w, cy + half_h, front - 0.012), "red")
    word = "CLOSED"
    cell_w, cell_h, gap = 0.078, 0.135, 0.017
    span = len(word) * cell_w + (len(word) - 1) * gap
    left = cx - span / 2
    z = front - 0.0275
    for index, letter in enumerate(word):
        lx = left + index * (cell_w + gap)
        for u0, v0, u1, v1 in LETTERS[letter]:
            front_quad(m, lx + u0 * cell_w, cy - cell_h / 2 + v0 * cell_h, lx + u1 * cell_w, cy - cell_h / 2 + v1 * cell_h, z, "white")
    m.tilt = None


# ---------------------------------------------------------------- the truck

# World metres, centred on the footprint, y up from the ground, hatch side -z, cab +x.
TRUCK_L, TRUCK_W = 1.30, 0.62
BODY_TOP = 0.86
TRUCK_PANEL = (-0.56, 0.66, 0.20, 0.84)  # x0, y0, x1, y1 on the -z side
TRUCK_TEXT = {"centre": [-0.18, 0.75, -0.3125], "size": [0.70, 0.13]}
TOQUE_BASE = BODY_TOP + 0.075


def add_truck(m: Mesh) -> None:
    hl, hw = TRUCK_L / 2, TRUCK_W / 2
    cab_x = 0.32
    # Chassis and wheels.
    box(m, (-hl + 0.03, 0.10, -hw + 0.02), (hl - 0.01, 0.18, hw - 0.02), "ink")
    for wx in (-0.40, 0.44):
        for wz in (-hw + 0.01, hw - 0.01):
            zdisc(m, wx, 0.13, 0.13, 0.13, wz - 0.045, wz + 0.045, "ink", sides=8)
    # Body: purple box, gold skirt and a gold cornice.
    box(m, (-hl, 0.16, -hw), (cab_x, BODY_TOP, hw), "purple")
    box(m, (-hl - 0.004, 0.16, -hw - 0.006), (cab_x, 0.25, hw + 0.006), "gold")
    box(m, (-hl - 0.004, BODY_TOP - 0.035, -hw - 0.006), (cab_x + 0.004, BODY_TOP, hw + 0.006), "gold")
    # Cab: a lower box with a windscreen and side windows, a bumper and two headlamps.
    box(m, (cab_x, 0.16, -hw), (hl, 0.40, hw), "purple_dark")
    box(m, (cab_x, 0.40, -hw), (cab_x + 0.19, 0.64, hw), "purple_dark")
    box(m, (cab_x + 0.19, 0.42, -hw + 0.04), (cab_x + 0.195, 0.60, hw - 0.04), "sky")
    for z in (-hw - 0.002, hw + 0.002):
        box(m, (cab_x + 0.03, 0.43, z - 0.003), (cab_x + 0.16, 0.60, z + 0.003), "sky")
    box(m, (hl - 0.005, 0.15, -hw - 0.01), (hl + 0.03, 0.22, hw + 0.01), "gold")
    for z in (-0.2, 0.2):
        box(m, (hl, 0.27, z - 0.04), (hl + 0.015, 0.33, z + 0.04), "gold_light")
    # Serving hatch on the -z side: a dark opening in a gold frame, a counter and a striped awning.
    hx0, hx1, hy0, hy1 = -0.52, 0.10, 0.28, 0.52
    box(m, (hx0, hy0, -hw - 0.004), (hx1, hy1, -hw + 0.002), "ink")
    box(m, (hx0 - 0.03, hy1, -hw - 0.012), (hx1 + 0.03, hy1 + 0.03, -hw), "gold")
    box(m, (hx0 - 0.03, hy0 - 0.03, -hw - 0.012), (hx0, hy1, -hw), "gold")
    box(m, (hx1, hy0 - 0.03, -hw - 0.012), (hx1 + 0.03, hy1, -hw), "gold")
    box(m, (hx0 - 0.05, hy0 - 0.03, -hw - 0.095), (hx1 + 0.05, hy0 - 0.005, -hw), "gold_deep")
    stripes = 6
    awn_x0, awn_x1 = hx0 - 0.05, hx1 + 0.05
    step = (awn_x1 - awn_x0) / stripes
    for i in range(stripes):
        xa, xb = awn_x0 + i * step, awn_x0 + (i + 1) * step
        swatch = "gold" if i % 2 == 0 else "white"
        corners = [(xa, 0.56, -hw), (xb, 0.56, -hw), (xb, 0.46, -hw - 0.12), (xa, 0.46, -hw - 0.12)]
        raised = [(x, y + 0.035, z) for x, y, z in corners]
        ring_prism(m, corners, raised, swatch)
        box(m, (xa, 0.40, -hw - 0.125), (xb, 0.46, -hw - 0.115), "purple_dark" if i % 2 == 0 else "gold_deep")
    # The blank name panel above the hatch: gold border, cream board (the game paints the name on it).
    x0, y0, x1, y1 = TRUCK_PANEL
    box(m, (x0 - 0.02, y0 - 0.02, -hw - 0.010), (x1 + 0.02, y1 + 0.02, -hw), "gold")
    box(m, (x0, y0, -hw - 0.0125), (x1, y1, -hw - 0.010), "cream")
    # Marquee bulbs along the cornice.
    for i in range(7):
        x = -0.60 + 0.19 * i
        diamond(m, (x, BODY_TOP - 0.018, -hw - 0.018), 0.014, "white" if i % 2 == 0 else "gold_light")
    # Roof: a gold slab, then the toque sign, flat like a signboard and bigger than the cab is tall.
    box(m, (-hl - 0.015, BODY_TOP, -hw - 0.02), (cab_x + 0.02, BODY_TOP + 0.035, hw + 0.02), "purple")
    box(m, (-hl - 0.015, BODY_TOP + 0.02, -hw - 0.02), (cab_x + 0.02, BODY_TOP + 0.035, -hw + 0.02), "gold")
    cx = -0.17
    box(m, (cx - 0.14, BODY_TOP + 0.035, -0.05), (cx + 0.14, TOQUE_BASE, 0.05), "purple_dark")
    lathe(m, (cx, TOQUE_BASE, 0.0), [(0.15, 0.0), (0.165, 0.08), (0.235, 0.17), (0.275, 0.29),
                                     (0.26, 0.38), (0.18, 0.45)], 0.46, "white", sides=10)
    for dx in (-0.09, 0.0, 0.09):
        box(m, (cx + dx - 0.008, TOQUE_BASE + 0.14, -0.131), (cx + dx + 0.008, TOQUE_BASE + 0.34, -0.116), "gray")
    # A little exhaust stack at the back.
    ring = 6
    bottom = [(-hl + 0.07 + 0.025 * math.cos(2 * math.pi * i / ring), BODY_TOP + 0.035,
               hw - 0.08 + 0.025 * math.sin(2 * math.pi * i / ring)) for i in range(ring)]
    ring_prism(m, bottom, [(x, y + 0.14, z) for x, y, z in bottom], "gray")


# ---------------------------------------------------------------- GLB output

def pad(data: bytes) -> bytes:
    return data + b"\0" * (-len(data) % 4)


def glb(mesh: Mesh, name: str) -> bytes:
    k = 1.0 / FURNITURE_SCALE
    positions = [(p[0] * k, p[1] * k, p[2] * k) for p in mesh.positions]
    pos = b"".join(struct.pack("<fff", *p) for p in positions)
    nor = b"".join(struct.pack("<fff", *n) for n in mesh.normals)
    uv = b"".join(struct.pack("<ff", *t) for t in mesh.uvs)
    idx = pad(b"".join(struct.pack("<H", i) for i in mesh.indices))
    blob = pos + nor + uv + idx
    xs = [p[0] for p in positions]
    ys = [p[1] for p in positions]
    zs = [p[2] for p in positions]
    n = len(positions)
    doc = {
        "asset": {"version": "2.0", "generator": "tools/build_copley_art.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0}],
        "meshes": [{"name": name, "primitives": [{
            "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3, "material": 0}]}],
        "materials": [{"name": "colormap", "doubleSided": True,
                       "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0.0,
                                                "roughnessFactor": 1.0}}],
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


def build(*adders) -> Mesh:
    m = Mesh()
    for adder in adders:
        adder(m)
    return m


def world_box(mesh: Mesh) -> dict:
    xs = [p[0] for p in mesh.positions]
    ys = [p[1] for p in mesh.positions]
    zs = [p[2] for p in mesh.positions]
    return {"min": [round(min(xs), 4), round(min(ys), 4), round(min(zs), 4)],
            "max": [round(max(xs), 4), round(max(ys), 4), round(max(zs), 4)],
            "size": [round(max(xs) - min(xs), 4), round(max(ys) - min(ys), 4), round(max(zs) - min(zs), 4)]}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    pieces = {
        "copley_truck": build(add_truck),
        "copley_sign": build(add_sign),
        "copley_closing_sign": build(add_sign, add_closed_board),
    }
    metrics = {"issue": 701, "furniture_scale": FURNITURE_SCALE, "budget": BUDGET,
               "units": "world metres (the file holds them divided by furniture_scale)", "assets": {}}
    for name, mesh in pieces.items():
        (OUT / f"{name}.glb").write_bytes(glb(mesh, name))
        entry = {"triangles": mesh.triangles(), "world_box": world_box(mesh)}
        panel = dict(TRUCK_TEXT if name == "copley_truck" else TEXT_AREA)
        panel["centre"] = [-panel["centre"][0], panel["centre"][1], panel["centre"][2]]
        entry["text"] = {"panel": panel, "faces": "-z"}
        metrics["assets"][name] = entry
        print(f"wrote {OUT / (name + '.glb')} ({mesh.triangles()} triangles)")
        if mesh.triangles() > BUDGET:
            raise SystemExit(f"{name} is over the {BUDGET} triangle budget")
    (OUT / "copley.metrics.json").write_text(json.dumps(metrics, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
